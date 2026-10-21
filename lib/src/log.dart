// Журнал %APPDATA%\Dartty\dartty.log: у exe без консоли это единственный способ увидеть ошибки.

import 'dart:io';

import 'settings.dart';

void logf(String message) {
  try {
    Directory(configDir()).createSync(recursive: true);
    final f = File('${configDir()}${Platform.pathSeparator}dartty.log');
    if (f.existsSync() && f.lengthSync() > 512 * 1024) f.deleteSync();
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    f.writeAsStringSync('$stamp $message\n', mode: FileMode.append, flush: true);
  } catch (_) {
    // журнал не должен ронять программу
  }
}
