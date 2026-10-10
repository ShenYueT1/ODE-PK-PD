# Kinetica — mechanistic PK/PD studio

A Flutter Windows desktop application for graduate-level exploration of nonlinear pharmacokinetics and pharmacodynamics. The defaults describe a **synthetic compound**, not an approved drug or validated clinical model.

## Start the app

On Windows, double-click **`Run Kinetica.cmd`** in this folder. It restores Flutter dependencies and starts the desktop application. Flutter must be on PATH; Visual Studio needs the **Desktop development with C++** workload. See [Flutter's Windows setup instructions](https://docs.flutter.dev/platform-integration/windows/setup).

Or open PowerShell in this folder:

```powershell
flutter pub get
flutter run -d windows --release
```

Developed against Flutter 3.41.9 / Dart 3.11.5. The project uses only the Flutter SDK at runtime. Python, CUDA, a server, API keys, and network access are not required to run a built application. Dependency restoration and initial Flutter setup need internet access.

**Build status:** The ODE engine has been executed and verified. Native Windows compilation and Flutter widget execution could not be completed inside the development sandbox because the standard Dart/Flutter launcher fails at Windows path canonicalization. A prebuilt EXE is therefore **not included**. The Windows runner, source, tests, and build script are supplied; run them in an ordinary local terminal. See [validation details](docs/VALIDATION.md).

## Included features

- **Full TMDD:** free drug, free target, reversible complex formation, receptor turnover, and complex internalization. Drug binding is modeled dynamically, without a quasi-equilibrium approximation.
- **Michaelis–Menten elimination:** a saturable pathway in parallel with linear clearance. Both are dimensionally consistent on a molar basis.
- **Nonlinear pharmacodynamics:** Hill Emax inhibition or stimulation, an effect-site delay, a changing baseline set point, and response turnover.
- **Virtual trials:** 100 patients by default, up to 500, with seeded lognormal clearance, central-volume and EC50 variation. Clearance and volume can be correlated. The shaded band is the pointwise 5th–95th percentile interval across virtual patients.
- **Dosing:** repeated IV bolus, first-order oral absorption, and finite IV infusions, including overlapping infusions and partial delivery at the simulation horizon.
- **Numerics:** adaptive Dormand–Prince 5(4), exact dose boundaries, integrated AUC and drug elimination, positivity checks, mass accounting, and explicit failures for infeasible or excessively stiff configurations.
- **Interface:** editable parameters with units, four presets, hover inspection, linear/log concentration axes, target engagement, cohort histograms and patient summaries, previous-run overlays, and recent-run restoration.
- **Analysis:** local ±5% finite-difference sensitivities for AUC and final response.
- **Files:** save/load complete experiment JSON; export trajectories and per-patient summaries to CSV. CSV exports include a companion configuration file for reproducibility.

## First experiment

1. The application automatically runs the default 100-patient synthetic TMDD experiment.
2. Select a scenario and adjust the dosing regimen in the left panel. Expand **Parameters & numerics** to edit disposition, binding, PD and population assumptions.
3. Click **Run experiment**. The displayed curves always belong to the last completed run; changed controls are marked **UNRUN CHANGES**.
4. Inspect **Virtual population** for exposure histograms and patient summaries. The **Model equations** page explains the mathematical assumptions and unit conversions.
5. Run a second experiment and enable **Overlay previous run** to compare typical-patient curves. Comparison values beyond the earlier run's horizon are omitted.
6. Choose **Files** to export or restore an experiment. The current export dialog accepts a full path. Existing files require confirmation.

The **Sensitivity** page uses the latest completed experiment, not unrun editor changes. It computes local elasticities of the typical individual. Parameter bounds also apply to perturbed values; near a boundary, choose a valid interior point before running this analysis.

## Laptop compatibility and performance

An RTX 5060 laptop is an appropriate target for this Windows application. The numerical workload runs on CPU isolates, with up to four workers; Flutter handles graphical rendering. There is no CUDA dependency or claim of GPU-accelerated ODE integration.

The supplied default 100-patient benchmark completed in **162 ms** in the local Dart VM measurement, with 27,264 accepted steps and 303 rejected steps across typical and virtual individuals. This is a measured development run, not a release benchmark or a guarantee for another laptop. See [benchmark.json](examples/default_trial/benchmark.json). Large cohorts, tighter tolerances, fast binding, and longer horizons increase work. Some extreme allowed combinations will exceed the explicit solver's step budget and report an error; an implicit stiff backend is outside this version's scope.

## Build and verify

```powershell
flutter pub get
dart test test/core_test.dart
flutter test test/charts_test.dart test/widget_test.dart
flutter analyze
flutter build windows --release
```

`Build Windows.cmd` performs dependency restoration, static analysis, tests, and the release build in sequence. Distribute the **entire** `build\windows\x64\runner\Release` directory, including its DLLs and `data` directory. The target machine also needs the appropriate Microsoft Visual C++ runtime, as described in [Flutter's Windows distribution documentation](https://docs.flutter.dev/platform-integration/windows/building).

For an independent numerical reference comparison:

```powershell
dart run tool/export_reference_cases.dart work/reference_cases.json
python -m pip install numpy scipy
python tool/validate_scipy_reference.py work/reference_cases.json --report work/reference_report.json
```

Python is used only for development validation. `dart run tool/benchmark.dart` regenerates a complete default example under `exports/example`.

## Project map

| Path | Purpose |
|---|---|
| `lib/main.dart` | Flutter desktop interface, experiment state, exports and sensitivity controls |
| `lib/core/simulation.dart` | Pure Dart model, adaptive solver, dosing, populations and summaries |
| `lib/ui/charts.dart` | Interactive time-series, interval and histogram rendering |
| `test/core_test.dart` | 21 analytical, conservation, convergence, event and reproducibility tests |
| `test/charts_test.dart`, `test/widget_test.dart` | Chart and desktop/compact UI checks |
| `docs/MODEL.md` | Equations, units, parameter assumptions, scientific references and limitations |
| `docs/VALIDATION.md` | What was actually executed and what remains unverified |
| `examples/default_trial` | Executed 100-patient example with JSON, CSV and benchmark results |
| `windows` | Native Windows runner and CMake build definitions |

The model is designed for scientific teaching and exploratory research. Parameter estimation, residual observation error, clinical qualification, and individualized dosing recommendations are not implemented.
