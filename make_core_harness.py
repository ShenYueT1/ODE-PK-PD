from pathlib import Path
root = Path(__file__).resolve().parent.parent
source = (root/'outputs/kinetica/test/core_test.dart').read_text(encoding='utf-8-sig')
source = source.replace("import 'package:test/test.dart';", "import 'dart:async';\nimport 'dart:io';")
source = source.replace("import '../lib/core/simulation.dart';", "import '../outputs/kinetica/lib/core/simulation.dart';")
source = source.replace('void main() {','void registerTests() {',1)
runner = r'''
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
'''
(root/'work/core_harness.dart').write_text(source+runner,encoding='utf-8')
