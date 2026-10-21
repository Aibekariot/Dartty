// Спрайты персонажа и их геометрия (см. assets/sprites/sprites.json).

import 'dart:typed_data';

import 'gfx.dart';
import 'png.dart';

/// Все спрайты, которые встраиваются в exe.
const spriteNames = [
  'idle', 'idle_blink', 'excited', 'pathos', 'focused', 'curious', 'sleep', 'offended', 'scared', 'angry', //
  'sad', 'blink', 'side', 'walk_body', 'walk_foot', 'edge', 'wave', 'yawn', 'proud',
  'bug_idle', 'bug_attack', 'bug_dead',
];

/// Холст спрайтов 360×312, лапы на линии y=304, персонаж по центру.
const double canvasW = 360, canvasH = 312;
const double footLine = 304;

/// Для позы edge: эта линия холста ставится на верхний край окна.
const double seatLine = 236;

/// Левый верхний угол лапки на холсте в покое (walk.footOffset).
const double footOffsetX = 184, footOffsetY = 274;

/// Верх капюшона над линией лап (для облачка).
const double headTop = 19;

/// Линия, которая стоит на поверхности (лапы или сиденье).
double contactLine(String pose) => pose == 'edge' ? seatLine : footLine;

class SpriteBank {
  final Map<String, Img> base;
  final _cache = <String, Img>{};

  SpriteBank(this.base);

  factory SpriteBank.fromPng(Map<String, Uint8List> files) =>
      SpriteBank({for (final e in files.entries) e.key: Img.fromRaw(decodePng(e.value))});

  /// Забыть уменьшенные копии (после смены размера).
  void clear() => _cache.clear();

  /// Спрайт, уменьшенный до масштаба [scale] качественным фильтром.
  Img get(String name, double scale) => _cache.putIfAbsent('$name@$scale', () {
        final b = base[name] ?? base['idle']!;
        return resize(b, (b.w * scale).round(), (b.h * scale).round());
      });

  /// Готовит один ещё не уменьшенный спрайт. false — всё уже готово.
  bool warmOne(Iterable<String> names, double scale) {
    for (final n in names) {
      if (base.containsKey(n) && !_cache.containsKey('$n@$scale')) {
        get(n, scale);
        return true;
      }
    }
    return false;
  }
}
