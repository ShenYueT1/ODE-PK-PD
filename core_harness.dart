import 'dart:convert';
import 'dart:math' as math;

import 'dart:async';
import 'dart:io';

import '../outputs/kinetica/lib/core/simulation.dart';

SimulationConfig linearConfig() => SimulationConfig(
  parameters: {
    'cl': .3,
    'vc': 3,
    'q': 0,
    'molecularWeight': 1000,
    'kbaseline': 0,
  },
  doseMg: 1,
  doseCount: 1,
  durationHours: 24,
  sampleHours: .5,
  enableTmdd: false,
  enableMichaelisMenten: false,
  enablePopulation: false,
  relativeTolerance: 1e-8,
  absoluteTolerance: 1e-10,
);

void expectRelative(double actual, double expected, [double tolerance = 3e-7]) {
  expect(actual, closeTo(expected, math.max(1e-8, expected.abs() * tolerance)));
}

void registerTests() {
  group('Analytical limits and dimensional consistency', () {
    test(
      'IV bolus matches exponential concentration and integrated finite AUC',
      () {
        final config = linearConfig();
        final simulation = simulateIndividual(config);
        final p = config.parameters;
        final dose = config.doseMg * 1e6 / p['molecularWeight']!;
        final c0 = dose / p['vc']!;
        final k = p['cl']! / p['vc']!;
        for (final point in simulation.points) {
          expectRelative(point.concentration, c0 * math.exp(-k * point.time));
          expectRelative(point.auc, c0 / k * (1 - math.exp(-k * point.time)));
        }
        expect(simulation.summary.cmax, c0);
        expect(simulation.summary.tmax, 0);
        expectRelative(simulation.summary.totalAdministeredNmol, dose);
      },
    );

    test('First-order oral absorption matches the Bateman equation', () {
      final config = linearConfig().copyWith(route: DoseRoute.oral);
      final simulation = simulateIndividual(config);
      final p = config.parameters;
      final dose = config.doseMg * 1e6 / p['molecularWeight']!;
      final k = p['cl']! / p['vc']!, ka = p['ka']!;
      final scale = p['bioavailability']! * dose / p['vc']! * ka / (ka - k);
      for (final point in simulation.points) {
        final expected =
            scale * (math.exp(-k * point.time) - math.exp(-ka * point.time));
        expectRelative(point.concentration, expected, 1e-6);
      }
      expectRelative(
        simulation.summary.totalAdministeredNmol,
        dose * p['bioavailability']!,
      );
      expect(simulation.points.first.concentration, 0);
      expectRelative(
        simulation.points.first.depotAmount,
        dose * p['bioavailability']!,
      );
    });

    test(
      'Pure Michaelis–Menten elimination satisfies its implicit solution',
      () {
        final config = SimulationConfig(
          parameters: {'cl': 0, 'q': 0},
          doseCount: 1,
          durationHours: 60,
          sampleHours: 1,
          enableTmdd: false,
          enablePopulation: false,
          relativeTolerance: 1e-9,
          absoluteTolerance: 1e-11,
        );
        final simulation = simulateIndividual(config), p = config.parameters;
        final c0 = simulation.points.first.concentration;
        for (final point in simulation.points) {
          final actual =
              point.concentration + p['km']! * math.log(point.concentration);
          final expected =
              c0 + p['km']! * math.log(c0) - p['vmax']! / p['vc']! * point.time;
          expectRelative(actual, expected, 1e-7);
        }
      },
    );

    test('Dose and molecular weight scale molar amounts correctly', () {
      final config = linearConfig();
      final reference = simulateIndividual(config).points.first;
      final doubledDose = simulateIndividual(
        config.copyWith(doseMg: 2),
      ).points.first;
      final doubledWeight = simulateIndividual(
        config.copyWith(
          parameters: {...config.parameters, 'molecularWeight': 2000},
        ),
      ).points.first;
      expect(doubledDose.concentration, reference.concentration * 2);
      expect(doubledWeight.concentration, reference.concentration / 2);
    });

    test('Effect-site equilibration matches its analytical convolution', () {
      final config = linearConfig();
      final simulation = simulateIndividual(config), p = config.parameters;
      final c0 = simulation.points.first.concentration;
      final k = p['cl']! / p['vc']!, ke0 = p['ke0']!;
      for (final point in simulation.points) {
        final expected =
            ke0 *
            c0 /
            (ke0 - k) *
            (math.exp(-k * point.time) - math.exp(-ke0 * point.time));
        expectRelative(point.effectSite, expected, 1e-6);
      }
    });
  });

  group('Dose events and mass conservation', () {
    test(
      'Repeated IV events are exact and use a post-dose sample convention',
      () {
        final config = linearConfig().copyWith(
          doseCount: 4,
          intervalHours: 3.7,
          durationHours: 14,
          sampleHours: .5,
        );
        final simulation = simulateIndividual(config);
        final p = config.parameters,
            dose = config.doseMg * 1e6 / config.parameters['molecularWeight']!;
        for (var i = 0; i < config.doseCount; i++) {
          expect(
            simulation.points.any(
              (point) => point.time == i * config.intervalHours,
            ),
            isTrue,
          );
        }
        for (final point in simulation.points) {
          var expected = 0.0;
          for (var i = 0; i < config.doseCount; i++) {
            final event = i * config.intervalHours;
            if (event <= point.time) {
              expected +=
                  dose /
                  p['vc']! *
                  math.exp(-p['cl']! / p['vc']! * (point.time - event));
            }
          }
          expectRelative(point.concentration, expected, 1e-6);
        }
      },
    );

    test(
      'Near-coincident floating-point event and output times do not underflow',
      () {
        final config = linearConfig().copyWith(
          intervalHours: .3,
          sampleHours: .1,
          durationHours: 2,
          doseCount: 4,
        );
        final simulation = simulateIndividual(config);
        expect(simulation.points.last.time, 2);
        expectRelative(simulation.summary.totalAdministeredNmol, 4000);
        expect(simulation.summary.massBalanceErrorNmol, lessThan(1e-6));
      },
    );

    test(
      'Infusion starts and stops agree with the closed-form one-compartment result',
      () {
        final config = linearConfig().copyWith(
          route: DoseRoute.infusion,
          infusionHours: 1.3,
          intervalHours: 2.2,
          doseCount: 2,
          durationHours: 4.8,
          sampleHours: .4,
        );
        final simulation = simulateIndividual(config), p = config.parameters;
        final dose = config.doseMg * 1e6 / p['molecularWeight']!;
        final rate = dose / config.infusionHours, k = p['cl']! / p['vc']!;
        for (final point in simulation.points) {
          var expected = 0.0;
          for (var i = 0; i < config.doseCount; i++) {
            final elapsed = point.time - i * config.intervalHours;
            if (elapsed <= 0) continue;
            final onTime = math.min(elapsed, config.infusionHours);
            final offTime = math.max(0.0, elapsed - config.infusionHours);
            expected +=
                rate /
                p['cl']! *
                (1 - math.exp(-k * onTime)) *
                math.exp(-k * offTime);
          }
          expectRelative(point.concentration, expected, 1e-6);
        }
        expect(simulation.points.any((p) => p.time == 1.3), isTrue);
        expect(simulation.points.any((p) => p.time == 3.5), isTrue);
        expectRelative(simulation.summary.totalAdministeredNmol, 2 * dose);
      },
    );

    test(
      'Overlapping infusions and horizon truncation track only delivered drug',
      () {
        final config = linearConfig().copyWith(
          route: DoseRoute.infusion,
          infusionHours: 3,
          intervalHours: 1,
          doseCount: 3,
          durationHours: 2.5,
          sampleHours: .5,
        );
        final simulation = simulateIndividual(config);
        final rate = 1000 / 3;
        expectRelative(
          simulation.summary.totalAdministeredNmol,
          rate * (2.5 + 1.5 + .5),
        );
        expect(simulation.summary.massBalanceErrorNmol, lessThan(1e-6));
      },
    );

    test('Full binding and distribution conserve drug in a closed system', () {
      final config = SimulationConfig(
        parameters: {'cl': 0, 'vmax': 0, 'kint': 0},
        doseCount: 1,
        durationHours: 72,
        sampleHours: .5,
        enablePopulation: false,
      );
      final simulation = simulateIndividual(config);
      final dose = config.doseMg * 1e6 / config.parameters['molecularWeight']!;
      for (final point in simulation.points) {
        expectRelative(point.totalDrugAmount, dose, 1e-8);
        expect(point.eliminatedAmount.abs(), lessThan(1e-8));
        expect(point.massBalanceError.abs(), lessThan(1e-6));
      }
      expect(simulation.points.last.complex, greaterThan(0));
      expect(simulation.points.last.peripheralConcentration, greaterThan(0));
    });

    test(
      'Full model accounts for drug lost through all elimination routes',
      () {
        final simulation = simulateIndividual(
          SimulationConfig(enablePopulation: false),
        );
        for (final point in simulation.points) {
          expect(point.massBalanceError.abs(), lessThan(1e-5));
          expect(point.receptorOccupancy, inInclusiveRange(0.0, 1.0));
          expect(point.concentration, greaterThanOrEqualTo(0));
          expect(point.target, greaterThanOrEqualTo(0));
          expect(point.response, greaterThanOrEqualTo(0));
        }
        expect(simulation.summary.eliminatedNmol, greaterThan(0));
        expect(simulation.diagnostics.rejectedSteps, greaterThanOrEqualTo(0));
      },
    );
  });

  group('Dynamic baseline and nonlinear pharmacodynamics', () {
    test(
      'Placebo baseline and lagged response match their coupled analytical solution',
      () {
        final config = SimulationConfig(
          doseMg: 0,
          doseCount: 1,
          enablePopulation: false,
          relativeTolerance: 1e-9,
          absoluteTolerance: 1e-11,
        );
        final simulation = simulateIndividual(config), p = config.parameters;
        final b0 = p['baseline0']!, binf = p['baselineAsymptote']!;
        final kb = p['kbaseline']!, kout = p['kout']!, delta = b0 - binf;
        for (final point in simulation.points) {
          final baseline = binf + delta * math.exp(-kb * point.time);
          final response =
              binf +
              delta *
                  (kout * math.exp(-kb * point.time) -
                      kb * math.exp(-kout * point.time)) /
                  (kout - kb);
          expectRelative(point.baseline, baseline, 1e-8);
          expectRelative(point.response, response, 1e-8);
          expect(point.concentration, 0);
          expect(point.effectSite, 0);
          expect(point.complex, 0);
          expectRelative(point.target, p['r0']!);
        }
        expect(
          simulation.points.last.response,
          lessThan(simulation.points.last.baseline),
        );
      },
    );

    test('Inhibition and stimulation bracket placebo response', () {
      final config = SimulationConfig(enablePopulation: false);
      final inhibition = simulateIndividual(config);
      final stimulation = simulateIndividual(
        config.copyWith(pdMode: PdMode.stimulation),
      );
      final placebo = simulateIndividual(config.copyWith(doseMg: 0));
      for (var i = 0; i < inhibition.points.length; i++) {
        expect(
          inhibition.points[i].response,
          lessThanOrEqualTo(placebo.points[i].response + 1e-4),
        );
        expect(
          stimulation.points[i].response,
          greaterThanOrEqualTo(placebo.points[i].response - 1e-4),
        );
      }
      expect(
        inhibition.summary.minResponse,
        lessThan(config.parameters['baseline0']!),
      );
      expect(
        stimulation.summary.maxResponse,
        greaterThan(placebo.summary.maxResponse),
      );
    });

    test(
      'Matched baseline and turnover rates satisfy the repeated-root solution',
      () {
        final config = SimulationConfig(
          parameters: {'kbaseline': .12, 'kout': .12},
          doseMg: 0,
          doseCount: 1,
          enablePopulation: false,
          relativeTolerance: 1e-9,
          absoluteTolerance: 1e-11,
        );
        final simulation = simulateIndividual(config), p = config.parameters;
        final k = p['kout']!, delta = p['baseline0']! - p['baselineAsymptote']!;
        for (final point in simulation.points) {
          final expected =
              p['baselineAsymptote']! +
              delta * math.exp(-k * point.time) * (1 + k * point.time);
          expectRelative(point.response, expected, 1e-8);
        }
      },
    );

    test('Tighter tolerances agree in the coupled nonlinear model', () {
      final config = SimulationConfig(enablePopulation: false);
      final reference = simulateIndividual(
        config.copyWith(relativeTolerance: 1e-9, absoluteTolerance: 1e-11),
      );
      final ordinary = simulateIndividual(config);
      expect(ordinary.points.length, reference.points.length);
      for (var i = 0; i < ordinary.points.length; i++) {
        expectRelative(
          ordinary.points[i].concentration,
          reference.points[i].concentration,
          3e-5,
        );
        expectRelative(
          ordinary.points[i].response,
          reference.points[i].response,
          3e-5,
        );
        expectRelative(
          ordinary.points[i].complex,
          reference.points[i].complex,
          3e-5,
        );
      }
      expectRelative(ordinary.summary.auc, reference.summary.auc, 3e-5);
    });
  });

  group('Population reproducibility and project validation', () {
    test(
      'Seeded lognormal draws repeat, change with seed, and respect zero variability',
      () {
        final config = SimulationConfig(populationSize: 25);
        final first = generatePopulationParameters(config),
            second = generatePopulationParameters(config);
        expect(first, equals(second));
        expect(
          first,
          isNot(
            equals(generatePopulationParameters(config.copyWith(seed: 43))),
          ),
        );
        expect(
          first.every((p) => p['cl']! > 0 && p['vc']! > 0 && p['ec50']! > 0),
          isTrue,
        );
        final constant = generatePopulationParameters(
          config.copyWith(
            parameters: {
              ...config.parameters,
              'omegaCl': 0,
              'omegaVc': 0,
              'omegaEc50': 0,
            },
          ),
        );
        for (final p in constant) {
          expect(p['cl'], config.parameters['cl']);
          expect(p['vc'], config.parameters['vc']);
          expect(p['ec50'], config.parameters['ec50']);
        }
      },
    );

    test('Population bands are ordered and collapse with zero variability', () {
      final config = SimulationConfig(
        populationSize: 5,
        durationHours: 12,
        doseCount: 1,
        parameters: {'omegaCl': 0, 'omegaVc': 0, 'omegaEc50': 0},
      );
      final result = runSimulation(config);
      expect(result.populationSummaries.length, 5);
      expect(result.diagnostics.patientCount, 5);
      for (var i = 0; i < result.typical.length; i++) {
        final band = result.populationBands[i], point = result.typical[i];
        expect(band.concentrationP05, point.concentration);
        expect(band.concentrationP50, point.concentration);
        expect(band.concentrationP95, point.concentration);
        expect(band.responseP05, point.response);
        expect(band.responseP95, point.response);
      }
      final variable = runSimulation(
        config.copyWith(parameters: SimulationConfig.defaultParameters),
      );
      for (final band in variable.populationBands) {
        expect(band.concentrationP05, lessThanOrEqualTo(band.concentrationP50));
        expect(band.concentrationP50, lessThanOrEqualTo(band.concentrationP95));
        expect(band.responseP05, lessThanOrEqualTo(band.responseP50));
        expect(band.responseP50, lessThanOrEqualTo(band.responseP95));
      }
      expect(
        variable.populationBands.first.concentrationP95,
        greaterThan(variable.populationBands.first.concentrationP05),
      );
    });

    test(
      'Native parallel pool preserves seeded population results exactly',
      () async {
        final config = SimulationConfig(
          populationSize: 8,
          durationHours: 12,
          doseCount: 1,
        );
        final serial = runSimulation(config);
        final parallel = await runSimulationParallel(config, workers: 3);
        expect(parallel.toCsv(), serial.toCsv());
        expect(parallel.populationSummaryCsv(), serial.populationSummaryCsv());
        expect(
          parallel.diagnostics.acceptedSteps,
          serial.diagnostics.acceptedSteps,
        );
        expect(parallel.populationParameters, serial.populationParameters);
      },
    );

    test('Typical-only run has no invented population band or patients', () {
      final result = runSimulation(SimulationConfig(enablePopulation: false));
      expect(result.populationBands, isEmpty);
      expect(result.populationSummaries, isEmpty);
      expect(result.populationParameters, isEmpty);
      expect(result.diagnostics.patientCount, 0);
      expect(result.toCsv().split('\n').first, contains('auc_nM_h'));
    });

    test('Project JSON round trips through plain JSON with all controls', () {
      final config = SimulationConfig(
        parameters: {'cl': .5},
        route: DoseRoute.oral,
        pdMode: PdMode.stimulation,
        doseMg: 25,
        intervalHours: 12,
        doseCount: 7,
        durationHours: 96,
        populationSize: 22,
        seed: 123,
        enableTmdd: false,
      );
      final json =
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>;
      final recovered = SimulationConfig.fromJson(json);
      expect(recovered.toJson(), config.toJson());
      expect(
        runSimulation(recovered.copyWith(enablePopulation: false)).config.route,
        DoseRoute.oral,
      );
    });

    test(
      'Invalid inputs fail explicitly without a plausible fabricated curve',
      () {
        for (final config in [
          SimulationConfig(parameters: {'vc': 0}),
          SimulationConfig(parameters: {'ec50': double.nan}),
          SimulationConfig(parameters: {'unknown': 1}),
          SimulationConfig(sampleHours: 0),
          SimulationConfig(populationSize: 0),
          SimulationConfig(doseCount: 0),
          SimulationConfig(seed: -1),
        ]) {
          expect(
            () => runSimulation(config),
            throwsA(isA<SimulationException>()),
          );
        }
        expect(
          () => simulateIndividual(linearConfig(), parameters: {'kint': -1}),
          throwsA(isA<SimulationException>()),
        );
        expect(
          () => SimulationConfig.fromJson({'schemaVersion': 2}),
          throwsA(isA<SimulationException>()),
        );
      },
    );
  });
}

class Check {
  Check(this.label, this.matches);
  final String label;
  final bool Function(dynamic) matches;
}
final _tests = <(String, FutureOr<void> Function())>[];
void group(String name, void Function() body) => body();
void test(String name, FutureOr<void> Function() body) => _tests.add((name,body));
bool same(dynamic a, dynamic b) {
  if(a is Map && b is Map) return a.length==b.length && a.keys.every((k)=>b.containsKey(k)&&same(a[k],b[k]));
  if(a is Iterable && b is Iterable) {final aa=a.toList(), bb=b.toList();return aa.length==bb.length&&List.generate(aa.length,(i)=>same(aa[i],bb[i])).every((v)=>v);}
  return a==b;
}
void expect(dynamic actual,dynamic expected) {
  if(!(expected is Check ? expected.matches(actual) : same(actual,expected))) throw StateError('Expected ${expected is Check ? expected.label : expected}; actual $actual');
}
Check closeTo(num value,num tolerance)=>Check('within $tolerance of $value',(a)=>a is num&&(a-value).abs()<=tolerance);
Check lessThan(num value)=>Check('< $value',(a)=>a is num&&a<value);
Check greaterThan(num value)=>Check('> $value',(a)=>a is num&&a>value);
Check lessThanOrEqualTo(num value)=>Check('<= $value',(a)=>a is num&&a<=value);
Check greaterThanOrEqualTo(num value)=>Check('>= $value',(a)=>a is num&&a>=value);
Check inInclusiveRange(num a,num b)=>Check('in [$a,$b]',(v)=>v is num&&v>=a&&v<=b);
Check equals(dynamic value)=>Check('equals $value',(a)=>same(a,value));
Check isNot(Check other)=>Check('not ${other.label}',(a)=>!other.matches(a));
Check contains(String value)=>Check('contains $value',(a)=>a is String&&a.contains(value));
Check isA<T>()=>Check('is $T',(a)=>a is T);
Check throwsA(Check error)=>Check('throws ${error.label}',(a){try{(a as Function)();return false;}catch(e){return error.matches(e);}});
final isTrue=Check('true',(a)=>a==true);
final isEmpty=Check('empty',(a)=>(a as Iterable).isEmpty);
Future<void> main(List<String> args) async {
  registerTests(); final results=<Map<String,Object>>[];
  for(final (name,body) in _tests) {
    try {await body(); stdout.writeln('PASS $name');results.add({'name':name,'passed':true});}
    catch(e,st){stderr.writeln('FAIL $name: $e\n$st');results.add({'name':name,'passed':false,'error':e.toString()});}
  }
  final passed=results.every((v)=>v['passed']==true);
  stdout.writeln('${results.where((r)=>r["passed"]==true).length}/${results.length} passed');
  if(args.isNotEmpty) File(args.first).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'runner':'dependency-free assertions over unchanged test bodies','passed':passed,'results':results}));
  exitCode=passed?0:1;
}
