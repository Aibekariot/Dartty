// Фоновый изолят для асинхронной работы (дальше здесь будет HTTP к локальному ИИ:
// Ollama, LM Studio, Claude API через dart:io HttpClient).
//
// Почему не await в GUI-потоке: после await изолят может продолжить работу на
// другом потоке ОС из пула Dart VM (проверено: при нагрузке поток меняется),
// а окна Win32 принимают сообщения только в потоке, который их создал. Поэтому
// GUI крутит синхронный цикл сообщений и никогда не отдаёт управление event loop,
// а всё асинхронное живёт здесь. Ответ приходит в окно управления через
// PostMessageW (он потокобезопасен): wParam — номер запроса, lParam — указатель
// на ответ в памяти HeapAlloc, его забирает [Worker.takeReply].

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'ffi.dart';
import 'win32.dart';

class Worker {
  final SendPort _to;
  Worker._(this._to);

  /// Запускает изолят. Вызывать до создания окон: это единственный await в программе.
  static Future<Worker> start() async {
    final rp = ReceivePort();
    await Isolate.spawn(_workerMain, rp.sendPort, debugName: 'dartty-worker');
    final to = await rp.first as SendPort;
    return Worker._(to);
  }

  /// Куда присылать ответы: окно и номер сообщения.
  void attach(int hwnd, int message) => _to.send(['attach', hwnd, message]);

  /// Отправляет задачу. Ответ придёт сообщением в окно из [attach].
  void request(int id, String kind, String payload) => _to.send(['job', id, kind, payload]);

  /// Читает ответ из lParam и освобождает память.
  static String takeReply(int lParam) {
    final p = Pointer<Uint8>.fromAddress(lParam);
    final len = p.cast<Uint32>().value;
    final text =
        utf8.decode(Uint8List.fromList(Pointer<Uint8>.fromAddress(lParam + 4).asTypedList(len)), allowMalformed: true);
    mem.free(p);
    return text;
  }
}

void _workerMain(SendPort back) {
  final rp = ReceivePort();
  back.send(rp.sendPort);
  var hwnd = 0, message = 0;
  rp.listen((m) async {
    final l = m as List;
    switch (l[0]) {
      case 'attach':
        hwnd = l[1] as int;
        message = l[2] as int;
      case 'job':
        final id = l[1] as int;
        String reply;
        try {
          reply = await _runJob(l[2] as String, l[3] as String);
        } catch (e) {
          reply = 'error: $e';
        }
        final bytes = utf8.encode(reply);
        final p = mem<Uint8>(bytes.length + 4);
        p.cast<Uint32>().value = bytes.length;
        Pointer<Uint8>.fromAddress(p.address + 4).asTypedList(bytes.length).setAll(0, bytes);
        if (hwnd == 0 || PostMessageW(hwnd, message, id, p.address) == 0) mem.free(p);
    }
  });
}

Future<String> _runJob(String kind, String payload) async {
  switch (kind) {
    case 'ping':
      // проверка моста: настоящая асинхронность (таймер event loop этого изолята)
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 'pong: $payload';
    default:
      return 'error: неизвестная задача $kind';
  }
}
