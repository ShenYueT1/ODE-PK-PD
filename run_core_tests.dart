import 'dart:io';
import 'package:test_core/src/direct_run.dart';
import '../outputs/kinetica/test/core_test.dart' as tests;
Future<void> main(List<String> args) async {
  exitCode = await directRunTests(tests.main) ? 0 : 1;
}
