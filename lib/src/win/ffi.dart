// Память и строки UTF-16 для Win32 без package:ffi.

import 'dart:ffi';

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _getProcessHeap = _kernel32.lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap');
final _heapAlloc =
    _kernel32.lookupFunction<Pointer Function(IntPtr, Uint32, IntPtr), Pointer Function(int, int, int)>('HeapAlloc');
final _heapFree =
    _kernel32.lookupFunction<Int32 Function(IntPtr, Uint32, Pointer), int Function(int, int, Pointer)>('HeapFree');
final int _heap = _getProcessHeap();

const _heapZeroMemory = 0x08;

/// Выделение памяти через HeapAlloc (память обнулена, выравнивание 16 байт).
final class HeapAllocator implements Allocator {
  const HeapAllocator();

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final p = _heapAlloc(_heap, _heapZeroMemory, byteCount < 1 ? 1 : byteCount);
    if (p.address == 0) throw StateError('HeapAlloc: не хватило памяти ($byteCount байт)');
    return p.cast();
  }

  @override
  void free(Pointer pointer) {
    if (pointer.address != 0) _heapFree(_heap, 0, pointer);
  }
}

const mem = HeapAllocator();

/// Временная память: всё, что выделено, освобождается разом в [releaseAll].
final class Arena implements Allocator {
  final _ptrs = <Pointer>[];

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final p = mem.allocate<T>(byteCount, alignment: alignment);
    _ptrs.add(p);
    return p;
  }

  @override
  void free(Pointer pointer) {}

  void releaseAll() {
    for (final p in _ptrs) {
      mem.free(p);
    }
    _ptrs.clear();
  }
}

R using<R>(R Function(Arena a) f) {
  final a = Arena();
  try {
    return f(a);
  } finally {
    a.releaseAll();
  }
}

/// Строка Dart → UTF-16 с нулём в конце.
Pointer<Uint16> wstr(String s, [Allocator a = mem]) {
  final units = s.codeUnits;
  final p = a<Uint16>(units.length + 1);
  final view = p.asTypedList(units.length + 1);
  view.setAll(0, units);
  view[units.length] = 0;
  return p;
}

/// UTF-16 длиной [len] → строка Dart.
String fromWstr(Pointer<Uint16> p, int len) => len <= 0 ? '' : String.fromCharCodes(p.asTypedList(len));

/// Копирует строку в массив фиксированной длины (с обрезкой и нулём в конце).
void copyWstr(Array<Uint16> dst, int cap, String s) {
  final units = s.codeUnits;
  final n = units.length < cap - 1 ? units.length : cap - 1;
  for (var i = 0; i < n; i++) {
    dst[i] = units[i];
  }
  dst[n] = 0;
}
