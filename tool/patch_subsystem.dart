// Переключает exe из консольного режима в оконный: Subsystem 3 (console) → 2 (GUI).
// Без этого при запуске Dartty открывалось бы чёрное окно консоли.
//
//   dart run tool/patch_subsystem.dart build/Dartty.exe

import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/patch_subsystem.dart <file.exe>');
    exit(2);
  }
  final f = File(args.first);
  final bytes = f.readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  String? err;
  if (bytes.length < 0x40 || bytes[0] != 0x4D || bytes[1] != 0x5A) err = 'нет сигнатуры MZ';
  final peOff = err == null ? bd.getUint32(0x3C, Endian.little) : 0;
  final optOff = peOff + 4 + 20; // сигнатура PE + COFF-заголовок
  final subOff = optOff + 68; // поле Subsystem одинаково для PE32 и PE32+
  if (err == null && subOff + 2 > bytes.length) err = 'заголовок PE за пределами файла';
  if (err == null && bd.getUint32(peOff, Endian.little) != 0x00004550) err = r'нет сигнатуры PE\0\0';
  final magic = err == null ? bd.getUint16(optOff, Endian.little) : 0;
  if (err == null && magic != 0x20b && magic != 0x10b) err = 'неизвестный Optional Header 0x${magic.toRadixString(16)}';
  final old = err == null ? bd.getUint16(subOff, Endian.little) : 0;
  if (err == null && old != 2 && old != 3) err = 'неожиданный Subsystem = $old';
  if (err != null) {
    stderr.writeln('${args.first}: $err');
    exit(1);
  }
  if (old == 2) {
    stdout.writeln('${args.first}: уже оконный (Subsystem = 2)');
    return;
  }
  bd.setUint16(subOff, 2, Endian.little);
  f.writeAsBytesSync(bytes, flush: true);
  stdout.writeln('${args.first}: Subsystem 3 (console) → 2 (GUI)');
}
