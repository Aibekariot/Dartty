// Плавная анимация Dartty: пружины, кроссфейд поз, походка вперевалку,
// моргание, дыхание и колыхание плаща. Без Win32 — только числа и картинки.

import 'dart:math' as math;
import 'dart:typed_data';

import 'gfx.dart';
import 'sprites.dart';

/// Значение тянется к цели с затуханием (жёсткость k, демпфирование d).
class Spring {
  double value, target, vel = 0;
  final double k, d;
  Spring(this.value, {this.k = 180, this.d = 14}) : target = value;

  void step(double dt) {
    var rest = dt;
    while (rest > 1e-9) {
      final h = math.min(rest, 1 / 240);
      vel += (-k * (value - target) - d * vel) * h;
      value += vel * h;
      rest -= h;
    }
  }

  void snap(double v) {
    value = target = v;
    vel = 0;
  }
}

/// Чего «мозг» хочет от картинки в этом кадре. Масштаб, подскок и наклон —
/// это цели: реальные значения тянутся к ним пружинами.
class MascotIntent {
  String pose = 'idle';
  bool flip = false;
  double sx = 1, sy = 1;

  /// Подскок вверх, экранные px.
  double offY = 0;

  /// Наклон, радианы (по часовой стрелке).
  double tilt = 0;

  /// Дрожь по x, экранные px (без пружины: она быстрая).
  double shakeX = 0;

  /// Сила колыхания плаща (px исходного холста) и его скорость (рад/с).
  double sway = 1, swaySpeed = 2.2;
  bool breathe = true;

  /// Пройденный путь (экранные px) и разгон ходьбы 0..1.
  double walkDist = 0, walkAmt = 0;
  double flash = 0;

  void reset() {
    pose = 'idle';
    flip = false;
    sx = sy = 1;
    offY = tilt = shakeX = flash = 0;
    sway = 1;
    swaySpeed = 2.2;
    breathe = true;
    walkAmt = 0;
  }
}

/// Готовые (квантованные) параметры кадра. Одинаковый [key] — одинаковая картинка.
class MascotFrame {
  final String pose, prev;
  final bool flip, prevFlip, blink;
  final double fade, sx, sy, tilt, phase, walkAmt, swayAmp, swayPhase, flash, fracX, fracY;
  final String key;

  MascotFrame({
    required this.pose,
    required this.flip,
    required this.prev,
    required this.prevFlip,
    required this.fade,
    required this.sx,
    required this.sy,
    required this.tilt,
    required this.phase,
    required this.walkAmt,
    required this.swayAmp,
    required this.swayPhase,
    required this.blink,
    required this.flash,
    required this.fracX,
    required this.fracY,
  }) : key = '$pose|$flip|$prev|$prevFlip|$fade|$sx|$sy|$tilt|$phase|$walkAmt|$swayAmp|$swayPhase|$blink|$flash|'
            '$fracX|$fracY';
}

double q(double v, double step) => (v / step).round() * step;

double _smooth(double t) => t * t * (3 - 2 * t);

class MascotAnimator {
  final math.Random rnd;
  MascotAnimator(this.rnd);

  /// Длительность кроссфейда между позами, с.
  static const fadeDur = 0.15;

  String pose = 'idle', prev = 'idle';
  bool flip = false, prevFlip = false;
  double fadeStart = -1e9;
  double now = 0;

  final sx = Spring(1, k: 220, d: 20);
  final sy = Spring(1, k: 220, d: 20);
  final offY = Spring(0, k: 600, d: 35);
  final tilt = Spring(0, k: 150, d: 16);

  /// Пружинное сжатие: приземление и «пружинка» при смене позы. Цель всегда 1.
  final squash = Spring(1, k: 180, d: 11);
  final sway = Spring(1, k: 25, d: 8);
  double swayPhase = 0;

  double nextBlink = 3.5, blinkUntil = 0, blink2At = 0;
  double walkDist = 0, walkAmt = 0, shakeX = 0, flash = 0;
  bool breathe = true;

  /// Приземление: сжатие по высоте до 1−amount и отскок с затуханием.
  void land(double amount) {
    squash.value = 1 - amount.clamp(0.0, 0.25);
    squash.vel = 0;
  }

  double get fade => ((now - fadeStart) / fadeDur).clamp(0.0, 1.0);

  void update(double now, double dt, MascotIntent it) {
    this.now = now;
    if (it.pose != pose || it.flip != flip) {
      prev = pose;
      prevFlip = flip;
      pose = it.pose;
      flip = it.flip;
      fadeStart = now;
      if (squash.value > 0.96) squash.value = 0.96;
    }
    sx.target = it.sx;
    sy.target = it.sy;
    offY.target = it.offY;
    tilt.target = it.tilt;
    sway.target = it.sway;
    for (final sp in [sx, sy, offY, tilt, squash, sway]) {
      sp.step(dt);
    }
    swayPhase = (swayPhase + it.swaySpeed * dt) % (2 * math.pi);
    walkDist = it.walkDist;
    walkAmt = it.walkAmt;
    shakeX = it.shakeX;
    flash = it.flash;
    breathe = it.breathe;

    // Моргание: каждые 3–6 с, иногда двойное.
    if (now >= nextBlink) {
      blinkUntil = now + 0.09 + rnd.nextDouble() * 0.04;
      blink2At = rnd.nextDouble() < 0.25 ? blinkUntil + 0.11 + rnd.nextDouble() * 0.05 : 0;
      nextBlink = now + 3 + rnd.nextDouble() * 3;
    }
    if (blink2At > 0 && now >= blink2At) {
      blinkUntil = now + 0.09 + rnd.nextDouble() * 0.03;
      blink2At = 0;
    }
  }

  /// Сдвиг картинки относительно точки опоры, экранные px.
  double get dx => shakeX;
  double get dy => -offY.value;

  MascotFrame frame(double s, double fracX, double fracY) {
    final f = fade;
    var syv = sy.value * squash.value;
    var sxv = sx.value * (1 + (1 - squash.value) * 0.7);
    if (breathe) syv *= 1 + 0.01 * math.sin(now * 2 * math.pi / 3);
    final walking = (pose == 'walk' || prev == 'walk') && walkAmt > 0.01;
    final phase = walking ? q((walkDist / s * math.pi / 20) % (2 * math.pi), 2 * math.pi / 96) : 0.0;
    final amp = q(sway.value, 0.2);
    return MascotFrame(
      pose: pose,
      flip: flip,
      prev: f < 1 ? prev : '',
      prevFlip: f < 1 ? prevFlip : false,
      fade: q(f, 1 / 24),
      sx: q(sxv, 0.003),
      sy: q(syv, 0.003),
      tilt: q(tilt.value, 0.0015),
      phase: phase,
      walkAmt: walking ? q(walkAmt, 0.05) : 0,
      swayAmp: amp,
      swayPhase: amp > 0 ? q(swayPhase, 2 * math.pi / (amp < 2 ? 24 : 48)) : 0,
      blink: now < blinkUntil && pose == 'idle' && f >= 1,
      flash: q(flash, 0.05),
      fracX: fracX,
      fracY: fracY,
    );
  }
}

/// Рисует кадр Dartty в холст. Точка опоры (ax, ay) — середина лап на поверхности.
class MascotRenderer {
  final SpriteBank bank;
  Img? _tmp;
  MascotRenderer(this.bank);

  void render(Img canvas, MascotFrame f, double s, double ax, double ay) {
    canvas.clear();
    _drawPose(canvas, f.pose, f.flip, f, s, ax, ay, blink: f.blink);
    if (f.fade < 1 && f.prev.isNotEmpty) {
      var tmp = _tmp;
      if (tmp == null || tmp.w != canvas.w || tmp.h != canvas.h) tmp = _tmp = Img(canvas.w, canvas.h);
      tmp.clear();
      _drawPose(tmp, f.prev, f.prevFlip, f, s, ax, ay, blink: false);
      mixInto(canvas, tmp, canvas, _smooth(f.fade));
    }
  }

  void _drawPose(Img dst, String pose, bool flip, MascotFrame f, double s, double ax, double ay,
      {required bool blink}) {
    final fs = flip ? -1.0 : 1.0;
    if (pose == 'walk') {
      _drawWalk(dst, fs, f, s, ax, ay);
      return;
    }
    final img = bank.get(blink ? 'idle_blink' : pose, s);
    final k = img.h / canvasH;
    final m = _bodyMatrix(ax, ay, img.w / 2, contactLine(pose) * k, fs, f.sx, f.sy, f.tilt, 0, 0, 0);
    drawImage(dst, img, m, sway: _swayTable(img, f.swayAmp * k, f.swayPhase), flash: f.flash);
  }

  /// Походка вперевалку: дальняя лапка (затемнена) позади тела, ближняя — спереди,
  /// тело покачивается вокруг точки между лапками и подпрыгивает дважды за шаг.
  void _drawWalk(Img dst, double fs, MascotFrame f, double s, double ax, double ay) {
    final body = bank.get('walk_body', s), foot = bank.get('walk_foot', s);
    final k = body.h / canvasH;
    final amt = f.walkAmt, c = math.cos(f.phase), sn = math.sin(f.phase);
    final lift = 3.0 * c.abs() * amt; // px холста: выше всего, когда одна лапка в воздухе
    final contact = math.pow(1 - c.abs(), 3) * 0.035 * amt; // сжатие в момент касания
    final waddle = 5 * math.pi / 180 * c * amt;
    final ancX = body.w / 2, ancY = footLine * k;

    Affine footM(double dx, double up) =>
        Affine.translate(ax, ay) *
        Affine.scale(fs, 1) *
        Affine.translate((footOffsetX + dx) * k - ancX, (footOffsetY - up) * k - ancY);

    drawImage(dst, foot, footM(-10 * sn * amt - 6, math.max(0, -c) * 5 * amt), tint: 0.6);
    final m = _bodyMatrix(ax, ay, ancX, ancY, fs, f.sx * (1 + contact * 0.6), f.sy * (1 - contact), f.tilt + waddle,
        fs * 39 * k, -8 * k, lift * k);
    drawImage(dst, body, m, sway: _swayTable(body, f.swayAmp * k, f.swayPhase), flash: f.flash);
    drawImage(dst, foot, footM(10 * sn * amt, math.max(0, c) * 5 * amt));
  }

  /// canvas = T(A+pv)·R(tilt)·T(−pv−lift)·S(fs·sx, sy)·T(−a)
  Affine _bodyMatrix(double ax, double ay, double aX, double aY, double fs, double sx, double sy, double tilt,
          double pvx, double pvy, double lift) =>
      Affine.translate(ax + pvx, ay + pvy) *
      Affine.rotate(tilt) *
      Affine.translate(-pvx, -pvy - lift) *
      Affine.scale(fs * sx, sy) *
      Affine.translate(-aX, -aY);

  /// Нижняя треть спрайта сдвигается по x синусоидой: от 0 у пояса до amp у подола.
  Float64List? _swayTable(Img img, double amp, double phase) {
    if (amp.abs() < 0.05) return null;
    final t = Float64List(img.h);
    final top = img.solidY0.toDouble(), bottom = img.solidY1.toDouble();
    final belt = top + (bottom - top) * 0.62, hem = bottom - (bottom - top) * 0.03;
    for (var v = belt.floor(); v < img.h; v++) {
      final p = ((v - belt) / (hem - belt)).clamp(0.0, 1.0);
      t[v] = amp * _smooth(p) * math.sin(phase - p * 1.4);
    }
    return t;
  }
}
