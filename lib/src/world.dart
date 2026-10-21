// Всё, что «мозгу» нужно от операционной системы. Реализация для Windows
// лежит в lib/src/win/, фальшивый рабочий стол — в tool/sim.dart.

import 'dart:typed_data';

import 'gfx.dart';

class WinInfo {
  final int h;
  final double l, t, r, b;
  final bool zoomed;
  const WinInfo(this.h, this.l, this.t, this.r, this.b, {this.zoomed = false});

  WinInfo moved({double dx = 0, double dy = 0}) => WinInfo(h, l + dx, t + dy, r + dx, b + dy, zoomed: zoomed);
}

typedef Rect4 = ({double l, double t, double r, double b});

class TextBlock {
  final Uint8List cov;
  final int w, h;
  const TextBlock(this.cov, this.w, this.h);
  static final empty = TextBlock(Uint8List(0), 0, 0);
}

abstract class World {
  double dpi();
  (double, double) cursor();

  /// Рабочая область монитора в точке (без панели задач).
  Rect4 workArea(double x, double y);
  List<WinInfo> candidateWindows();
  WinInfo? windowAlive(int h);
  int rootAt(double x, double y);
  bool ownWindow(int h);
  double idleSeconds();

  /// Процесс и заголовок активного окна.
  (String, String) foreground();
  bool fullscreen();
  TextBlock renderText(String text, {required bool bold, required int px, required int maxW});
  void setAutostart(bool on);
  void notify(String title, String text);
  void quit();
}

/// Картинка одного прозрачного окна и его положение на экране.
class Layer {
  Img? img;
  bool dirty = false;
  int x = 0, y = 0;
  bool visible = false;
  int alpha = 255;
}
