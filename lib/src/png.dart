// Мини-декодер и кодер PNG без пакетов: распаковка через ZLibCodec из dart:io.
// Декодер понимает то, что реально лежит в assets: 8 бит на канал, без
// чересстрочности, RGBA (тип 6), RGB (2), палитра (3), серый (0, 4).

import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

class RawImage {
  final int width, height;

  /// Обычный (не premultiplied) RGBA, 4 байта на пиксель.
  final Uint8List rgba;

  RawImage(this.width, this.height, this.rgba);
}

class PngFormatException implements Exception {
  final String message;
  PngFormatException(this.message);
  @override
  String toString() => 'PNG: $message';
}

const _signature = [137, 80, 78, 71, 13, 10, 26, 10];

RawImage decodePng(Uint8List bytes) {
  if (bytes.length < 8) throw PngFormatException('слишком короткий файл');
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _signature[i]) throw PngFormatException('нет сигнатуры');
  }
  final bd = ByteData.sublistView(bytes);
  var pos = 8;
  var width = 0, height = 0, depth = 0, colorType = 0, interlace = 0;
  Uint8List? palette;
  Uint8List? trns;
  final idat = BytesBuilder(copy: false);
  while (pos + 8 <= bytes.length) {
    final len = bd.getUint32(pos);
    final type = String.fromCharCodes(bytes, pos + 4, pos + 8);
    final data = Uint8List.sublistView(bytes, pos + 8, pos + 8 + len);
    pos += 12 + len;
    switch (type) {
      case 'IHDR':
        final h = ByteData.sublistView(data);
        width = h.getUint32(0);
        height = h.getUint32(4);
        depth = data[8];
        colorType = data[9];
        interlace = data[12];
      case 'PLTE':
        palette = data;
      case 'tRNS':
        trns = data;
      case 'IDAT':
        idat.add(data);
      case 'IEND':
        pos = bytes.length;
    }
  }
  if (width == 0 || height == 0) throw PngFormatException('нет IHDR');
  if (depth != 8) throw PngFormatException('поддерживается только 8 бит, а тут $depth');
  if (interlace != 0) throw PngFormatException('чересстрочный PNG не поддерживается');
  final channels = switch (colorType) {
    0 => 1,
    2 => 3,
    3 => 1,
    4 => 2,
    6 => 4,
    _ => throw PngFormatException('неизвестный тип цвета $colorType'),
  };
  final raw = Uint8List.fromList(ZLibCodec().decode(idat.takeBytes()));
  final stride = width * channels;
  if (raw.length < (stride + 1) * height) throw PngFormatException('данные обрезаны');
  _unfilter(raw, stride, height, channels);

  final out = Uint8List(width * height * 4);
  var o = 0;
  for (var y = 0; y < height; y++) {
    var s = y * (stride + 1) + 1;
    for (var x = 0; x < width; x++) {
      switch (colorType) {
        case 6:
          out[o] = raw[s];
          out[o + 1] = raw[s + 1];
          out[o + 2] = raw[s + 2];
          out[o + 3] = raw[s + 3];
        case 2:
          out[o] = raw[s];
          out[o + 1] = raw[s + 1];
          out[o + 2] = raw[s + 2];
          out[o + 3] = 255;
        case 3:
          final i = raw[s];
          final p = palette!;
          out[o] = p[i * 3];
          out[o + 1] = p[i * 3 + 1];
          out[o + 2] = p[i * 3 + 2];
          out[o + 3] = (trns != null && i < trns.length) ? trns[i] : 255;
        case 0:
          out[o] = out[o + 1] = out[o + 2] = raw[s];
          out[o + 3] = 255;
        case 4:
          out[o] = out[o + 1] = out[o + 2] = raw[s];
          out[o + 3] = raw[s + 1];
      }
      s += channels;
      o += 4;
    }
  }
  return RawImage(width, height, out);
}

void _unfilter(Uint8List d, int stride, int height, int bpp) {
  final row = stride + 1;
  for (var y = 0; y < height; y++) {
    final start = y * row + 1;
    final prev = start - row; // начало предыдущей строки (если y > 0)
    final f = d[start - 1];
    switch (f) {
      case 0:
        break;
      case 1: // Sub
        for (var i = bpp; i < stride; i++) {
          d[start + i] = (d[start + i] + d[start + i - bpp]) & 0xff;
        }
      case 2: // Up
        if (y == 0) break;
        for (var i = 0; i < stride; i++) {
          d[start + i] = (d[start + i] + d[prev + i]) & 0xff;
        }
      case 3: // Average
        for (var i = 0; i < stride; i++) {
          final a = i >= bpp ? d[start + i - bpp] : 0;
          final b = y > 0 ? d[prev + i] : 0;
          d[start + i] = (d[start + i] + ((a + b) >> 1)) & 0xff;
        }
      case 4: // Paeth
        for (var i = 0; i < stride; i++) {
          final a = i >= bpp ? d[start + i - bpp] : 0;
          final b = y > 0 ? d[prev + i] : 0;
          final c = (i >= bpp && y > 0) ? d[prev + i - bpp] : 0;
          final p = a + b - c;
          final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
          final pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
          d[start + i] = (d[start + i] + pr) & 0xff;
        }
      default:
        throw PngFormatException('неизвестный фильтр $f');
    }
  }
}

/// Кодирует RGBA (не premultiplied) в PNG. Нужен симуляции для снимков.
Uint8List encodePng(int width, int height, Uint8List rgba) {
  final stride = width * 4;
  final raw = Uint8List((stride + 1) * height);
  for (var y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 1; // Sub: хорошо жмётся
    final s = y * stride, d = y * (stride + 1) + 1;
    for (var i = 0; i < stride; i++) {
      final left = i >= 4 ? rgba[s + i - 4] : 0;
      raw[d + i] = (rgba[s + i] - left) & 0xff;
    }
  }
  final out = BytesBuilder();
  out.add(_signature);
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(ZLibCodec(level: 6).encode(raw)));
  _chunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final head = ByteData(8)..setUint32(0, data.length);
  final t = type.codeUnits;
  for (var i = 0; i < 4; i++) {
    head.setUint8(4 + i, t[i]);
  }
  out.add(head.buffer.asUint8List());
  out.add(data);
  var crc = 0xffffffff;
  for (final b in t) {
    crc = _crcTable[(crc ^ b) & 0xff] ^ (crc >> 8);
  }
  for (final b in data) {
    crc = _crcTable[(crc ^ b) & 0xff] ^ (crc >> 8);
  }
  out.add((ByteData(4)..setUint32(0, crc ^ 0xffffffff)).buffer.asUint8List());
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();
