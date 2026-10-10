import 'dart:io';
import 'package:dart_style/dart_style.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.first).absolute.path;
  final files = Directory(root).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart') && !f.path.contains('.dart_tool')).toList();
  final formatter = DartFormatter(languageVersion: DartFormatter.latestLanguageVersion);
  for (final file in files) {
    try { file.writeAsStringSync(formatter.format(file.readAsStringSync())); }
    catch (e) { stderr.writeln('FORMAT ERROR ${file.path}: $e'); exitCode = 1; }
  }
  if (exitCode != 0) return;
  stdout.writeln('Formatted ${files.length} Dart sources.');
  final collection = AnalysisContextCollection(includedPaths: [root], sdkPath: r'C:\flutter\bin\cache\dart-sdk');
  var count = 0;
  for (final file in files) {
    final result = await collection.contextFor(file.absolute.path).currentSession.getResolvedUnit(file.absolute.path);
    if (result is ResolvedUnitResult) {
      for (final error in result.diagnostics) {
        final location = result.lineInfo.getLocation(error.offset);
        stdout.writeln('${file.path}:${location.lineNumber}:${location.columnNumber}: ${error.diagnosticCode.severity.name} ${error.message}');
        count++;
      }
    } else { stdout.writeln('Analysis returned $result'); }
  }
  stdout.writeln('Analysis diagnostics: $count');
}

