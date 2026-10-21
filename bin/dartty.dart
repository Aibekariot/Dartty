// Dartty — маскот-компаньон для рабочего стола Windows.

import 'dart:io';

import 'package:dartty/src/win/runner.dart';

Future<void> main(List<String> args) async {
  if (!Platform.isWindows) {
    stderr.writeln('Dartty работает только в Windows. Поведение можно проверить: dart run tool/sim.dart');
    exit(1);
  }
  await runDartty(args);
}
