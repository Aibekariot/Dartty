// assets/ → lib/src/assets_data.dart: картинки встраиваются в exe (base64 → Uint8List).
//
//   dart run tool/embed_assets.dart

import 'dart:convert';
import 'dart:io';

import 'package:dartty/src/sprites.dart';

void main() {
  final files = <String, String>{
    for (final n in spriteNames) n: 'assets/sprites/$n.png',
    'icon_app': 'assets/icons/app.ico',
    'icon_tray': 'assets/icons/tray.ico',
  };
  final out = StringBuffer()
    ..writeln('// СГЕНЕРИРОВАНО tool/embed_assets.dart — не править руками (файл в .gitignore).')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln('const Map<String, String> assetData = {');
  var total = 0;
  for (final e in files.entries) {
    final f = File(e.value);
    if (!f.existsSync()) {
      stderr.writeln('нет файла ${e.value}');
      exit(1);
    }
    final bytes = f.readAsBytesSync();
    total += bytes.length;
    final b64 = base64Encode(bytes);
    out.writeln("  '${e.key}':");
    for (var i = 0; i < b64.length; i += 4000) {
      final end = i + 4000 < b64.length ? i + 4000 : b64.length;
      out.writeln("      '${b64.substring(i, end)}'");
    }
    out.writeln('      ,');
  }
  out.writeln('};');
  File('lib/src/assets_data.dart').writeAsStringSync(out.toString());
  stdout.writeln('встроено ${files.length} файлов, ${(total / 1024).round()} КБ → lib/src/assets_data.dart');
}
