// Простая 2D-графика без зависимостей: картинки хранятся в формате
// premultiplied BGRA — ровно так, как их ждёт UpdateLayeredWindow.

import 'dart:math' as math;
import 'dart:typed_data';

import 'png.dart';

class Img {
  final int w, h;

  /// BGRA, premultiplied, stride = w*4.
  final Uint8List pix;
  late final Uint32List pix32 = pix.buffer.asUint32List(pix.offsetInBytes, w * h);

  /// Прямоугольник ненулевых пикселей (для ускорения рисования).
  int bx0 = 0, by0 = 0, bx1 = 0, by1 = 0;

  /// Строки, где есть заметно непрозрачные пиксели (тело без слабого свечения).
  int solidY0 = 0, solidY1 = 0;

  Img(int w, int h) : this._(math.max(1, w), math.max(1, h));
  Img._(this.w, this.h) : pix = Uint8List(w * h * 4) {
    bx1 = w;
    by1 = h;
  }

  void clear() => pix.fillRange(0, pix.length, 0);

  factory Img.fromRaw(RawImage r) {
    final m = Img(r.width, r.height);
    final s = r.rgba, d = m.pix;
    for (var i = 0; i < s.length; i += 4) {
      final a = s[i + 3];
      d[i] = (s[i + 2] * a + 127) ~/ 255;
      d[i + 1] = (s[i + 1] * a + 127) ~/ 255;
      d[i + 2] = (s[i] * a + 127) ~/ 255;
      d[i + 3] = a;
    }
    m.computeBounds();
    return m;
  }

  /// Обычный RGBA (для сохранения в PNG).
  Uint8List toRgba() {
    final out = Uint8List(w * h * 4);
    for (var i = 0; i < pix.length; i += 4) {
      final a = pix[i + 3];
      if (a == 0) continue;
      out[i] = math.min(255, (pix[i + 2] * 255 + a ~/ 2) ~/ a);
      out[i + 1] = math.min(255, (pix[i + 1] * 255 + a ~/ 2) ~/ a);
      out[i + 2] = math.min(255, (pix[i] * 255 + a ~/ 2) ~/ a);
      out[i + 3] = a;
    }
    return out;
  }

  void computeBounds() {
    var x0 = w, y0 = h, x1 = 0, y1 = 0, s0 = h, s1 = 0;
    final p = pix32;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final a = p[row + x] >>> 24;
        if (a > 160) {
          if (y < s0) s0 = y;
          s1 = y + 1;
        }
        if (a != 0) {
          if (x < x0) x0 = x;
          if (x + 1 > x1) x1 = x + 1;
          if (y < y0) y0 = y;
          y1 = y + 1;
        }
      }
    }
    if (x1 <= x0) {
      x0 = y0 = x1 = y1 = 0;
    }
    bx0 = x0;
    by0 = y0;
    bx1 = x1;
    by1 = y1;
    solidY0 = s1 > s0 ? s0 : y0;
    solidY1 = s1 > s0 ? s1 : y1;
  }
}

// ---------- Ресайз (сепарабельный треугольный фильтр, как в Go-версии) ----------

Img resize(Img src, int w, int h) {
  w = math.max(1, w);
  h = math.max(1, h);
  final tmp = _resampleAxis(src.pix, src.w, src.h, w, true);
  final out = _resampleAxis(tmp, w, src.h, h, false);
  final m = Img(w, h);
  m.pix.setAll(0, out);
  m.computeBounds();
  return m;
}

Uint8List _resampleAxis(Uint8List pix, int sw, int sh, int dn, bool horiz) {
  final sn = horiz ? sw : sh;
  final scale = sn / dn;
  final support = math.max(1.0, scale);
  final tapIdx = <Int32List>[];
  final tapW = <Float64List>[];
  for (var d = 0; d < dn; d++) {
    final c = (d + 0.5) * scale - 0.5;
    final lo = (c - support).floor(), hi = (c + support).ceil();
    final idx = <int>[];
    final ws = <double>[];
    var sum = 0.0;
    for (var i = lo; i <= hi; i++) {
      if (i < 0 || i >= sn) continue;
      final wt = 1 - (i - c).abs() / support;
      if (wt <= 0) continue;
      idx.add(i);
      ws.add(wt);
      sum += wt;
    }
    tapIdx.add(Int32List.fromList(idx));
    tapW.add(Float64List.fromList([for (final x in ws) x / sum]));
  }
  final ow = horiz ? dn : sw, oh = horiz ? sh : dn;
  final out = Uint8List(ow * oh * 4);
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      final ti = horiz ? tapIdx[x] : tapIdx[y];
      final tw = horiz ? tapW[x] : tapW[y];
      var a0 = 0.0, a1 = 0.0, a2 = 0.0, a3 = 0.0;
      for (var k = 0; k < ti.length; k++) {
        final o = horiz ? (y * sw + ti[k]) * 4 : (ti[k] * sw + x) * 4;
        final wt = tw[k];
        a0 += pix[o] * wt;
        a1 += pix[o + 1] * wt;
        a2 += pix[o + 2] * wt;
        a3 += pix[o + 3] * wt;
      }
      final o = (y * ow + x) * 4;
      final a = _c255(a3);
      out[o + 3] = a;
      out[o] = math.min(_c255(a0), a);
      out[o + 1] = math.min(_c255(a1), a);
      out[o + 2] = math.min(_c255(a2), a);
    }
  }
  return out;
}

int _c255(double v) => v <= 0 ? 0 : (v >= 255 ? 255 : (v + 0.5).toInt());

Img flipH(Img src) {
  final m = Img(src.w, src.h);
  for (var y = 0; y < src.h; y++) {
    final row = y * src.w;
    for (var x = 0; x < src.w; x++) {
      m.pix32[row + src.w - 1 - x] = src.pix32[row + x];
    }
  }
  m.computeBounds();
  return m;
}

// ---------- Аффинные преобразования ----------

/// x' = a·x + b·y + c,  y' = d·x + e·y + f
class Affine {
  final double a, b, c, d, e, f;
  const Affine(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = Affine(1, 0, 0, 0, 1, 0);

  factory Affine.translate(double x, double y) => Affine(1, 0, x, 0, 1, y);
  factory Affine.scale(double sx, double sy) => Affine(sx, 0, 0, 0, sy, 0);
  factory Affine.rotate(double rad) {
    final cs = math.cos(rad), sn = math.sin(rad);
    return Affine(cs, -sn, 0, sn, cs, 0);
  }

  /// Сначала применяется [o], потом this.
  Affine operator *(Affine o) => Affine(
        a * o.a + b * o.d,
        a * o.b + b * o.e,
        a * o.c + b * o.f + c,
        d * o.a + e * o.d,
        d * o.b + e * o.e,
        d * o.c + e * o.f + f,
      );

  Affine inverse() {
    final det = a * e - b * d;
    if (det.abs() < 1e-12) return identity;
    final ia = e / det, ib = -b / det, id = -d / det, ie = a / det;
    return Affine(ia, ib, -(ia * c + ib * f), id, ie, -(id * c + ie * f));
  }

  double tx(double x, double y) => a * x + b * y + c;
  double ty(double x, double y) => d * x + e * y + f;
}

/// Рисует [src] на [dst] с преобразованием [m] (координаты src → dst),
/// билинейной выборкой и смешиванием «поверх».
///
/// [sway] — сдвиг по x для каждой строки исходника (колыхание плаща):
/// это сетка из горизонтальных полос, а не поворот всего спрайта.
/// [tint] затемняет цвет (1 — как есть), [flash] осветляет к белому (0..1).
void drawImage(Img dst, Img src, Affine m, {double opacity = 1, double tint = 1, double flash = 0, Float64List? sway}) {
  if (opacity <= 0 || src.bx1 <= src.bx0) return;
  final inv = m.inverse();
  var maxSway = 0.0;
  if (sway != null) {
    for (final s in sway) {
      if (s.abs() > maxSway) maxSway = s.abs();
    }
  }
  // Область на dst: образ рамки непрозрачных пикселей.
  final bx0 = src.bx0 - 1 - maxSway, by0 = src.by0 - 1.0;
  final bx1 = src.bx1 + 1 + maxSway, by1 = src.by1 + 1.0;
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final (px, py) in [(bx0, by0), (bx1, by0), (bx0, by1), (bx1, by1)]) {
    final x = m.tx(px, py), y = m.ty(px, py);
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  final x0 = math.max(0, minX.floor()), y0 = math.max(0, minY.floor());
  final x1 = math.min(dst.w, maxX.ceil()), y1 = math.min(dst.h, maxY.ceil());
  if (x1 <= x0 || y1 <= y0) return;

  final sp = src.pix32, dp = dst.pix32;
  final sw = src.w, sh = src.h;
  final op = (opacity.clamp(0.0, 1.0) * 256).round();
  final tn = (tint.clamp(0.0, 1.0) * 256).round();
  final fl = (flash.clamp(0.0, 1.0) * 256).round();
  final plain = op == 256 && tn == 256 && fl == 0;
  final ia = inv.a, id = inv.d;

  for (var y = y0; y < y1; y++) {
    final py = y + 0.5;
    var u = inv.a * (x0 + 0.5) + inv.b * py + inv.c - 0.5;
    var v = inv.d * (x0 + 0.5) + inv.e * py + inv.f - 0.5;
    final drow = y * dst.w;
    for (var x = x0; x < x1; x++, u += ia, v += id) {
      var uu = u;
      if (sway != null) {
        var vi = (v + 0.5).floor();
        if (vi < 0) vi = 0;
        if (vi >= sh) vi = sh - 1;
        uu -= sway[vi];
      }
      final fu = uu.floor(), fv = v.floor();
      if (fu < -1 || fv < -1 || fu >= sw || fv >= sh) continue;
      final wx = ((uu - fu) * 256).toInt(), wy = ((v - fv) * 256).toInt();
      final p00 = (fu >= 0 && fv >= 0) ? sp[fv * sw + fu] : 0;
      final p10 = (fu + 1 < sw && fv >= 0) ? sp[fv * sw + fu + 1] : 0;
      final p01 = (fu >= 0 && fv + 1 < sh) ? sp[(fv + 1) * sw + fu] : 0;
      final p11 = (fu + 1 < sw && fv + 1 < sh) ? sp[(fv + 1) * sw + fu + 1] : 0;
      if ((p00 | p10 | p01 | p11) == 0) continue;
      final w00 = (256 - wx) * (256 - wy), w10 = wx * (256 - wy);
      final w01 = (256 - wx) * wy, w11 = wx * wy;
      var cb = ((p00 & 0xff) * w00 + (p10 & 0xff) * w10 + (p01 & 0xff) * w01 + (p11 & 0xff) * w11 + 32768) >> 16;
      var cg = (((p00 >> 8) & 0xff) * w00 +
              ((p10 >> 8) & 0xff) * w10 +
              ((p01 >> 8) & 0xff) * w01 +
              ((p11 >> 8) & 0xff) * w11 +
              32768) >>
          16;
      var cr = (((p00 >> 16) & 0xff) * w00 +
              ((p10 >> 16) & 0xff) * w10 +
              ((p01 >> 16) & 0xff) * w01 +
              ((p11 >> 16) & 0xff) * w11 +
              32768) >>
          16;
      var ca = ((p00 >>> 24) * w00 + (p10 >>> 24) * w10 + (p01 >>> 24) * w01 + (p11 >>> 24) * w11 + 32768) >> 16;
      if (ca == 0) continue;
      if (!plain) {
        if (tn != 256) {
          cb = (cb * tn) >> 8;
          cg = (cg * tn) >> 8;
          cr = (cr * tn) >> 8;
        }
        if (fl != 0) {
          cb += ((ca - cb) * fl) >> 8;
          cg += ((ca - cg) * fl) >> 8;
          cr += ((ca - cr) * fl) >> 8;
        }
        if (op != 256) {
          cb = (cb * op) >> 8;
          cg = (cg * op) >> 8;
          cr = (cr * op) >> 8;
          ca = (ca * op) >> 8;
          if (ca == 0) continue;
        }
      }
      final di = drow + x;
      if (ca >= 255) {
        dp[di] = cb | (cg << 8) | (cr << 16) | (0xff << 24);
        continue;
      }
      final dv = dp[di];
      final rest = 255 - ca;
      final ob = cb + _div255((dv & 0xff) * rest);
      final og = cg + _div255(((dv >> 8) & 0xff) * rest);
      final or = cr + _div255(((dv >> 16) & 0xff) * rest);
      final oa = ca + _div255((dv >>> 24) * rest);
      dp[di] = (ob > 255 ? 255 : ob) |
          ((og > 255 ? 255 : og) << 8) |
          ((or > 255 ? 255 : or) << 16) |
          ((oa > 255 ? 255 : oa) << 24);
    }
  }
}

int _div255(int t) {
  t += 128;
  return (t + (t >> 8)) >> 8;
}

/// out = a·(1−t) + b·t — честный кроссфейд двух кадров (без «провала» прозрачности).
void mixInto(Img out, Img a, Img b, double t) {
  final w = (t.clamp(0.0, 1.0) * 256).round();
  final pa = a.pix, pb = b.pix, po = out.pix;
  final iw = 256 - w;
  for (var i = 0; i < po.length; i++) {
    po[i] = (pa[i] * iw + pb[i] * w + 128) >> 8;
  }
}

/// Рисует src так, что его точка (ax, ay) попадает в (dx, dy) на dst,
/// с масштабом sx, sy (как DrawSprite в Go-версии).
void drawSprite(Img dst, Img src, double ax, double ay, double dx, double dy,
    {double sx = 1, double sy = 1, double opacity = 1, double flash = 0}) {
  final m = Affine.translate(dx, dy) * Affine.scale(sx, sy) * Affine.translate(-ax, -ay);
  drawImage(dst, src, m, opacity: opacity, flash: flash);
}

// ---------- Фигуры ----------

/// Обычный (не premultiplied) цвет.
class Rgba {
  final int r, g, b, a;
  const Rgba(this.r, this.g, this.b, this.a);
}

/// Функция расстояния до фигуры: < 0 внутри, > 0 снаружи (в пикселях).
typedef Sdf = double Function(double x, double y);

/// Закрашивает фигуру по функции расстояния с аналитическим сглаживанием краёв
/// (покрытие пикселя = 0.5 − расстояние). Быстрее суперсэмплинга в 16 раз.
void fillSdf(Img dst, int x0, int y0, int x1, int y1, Rgba col, Sdf sd) {
  x0 = math.max(0, x0);
  y0 = math.max(0, y0);
  x1 = math.min(dst.w, x1);
  y1 = math.min(dst.h, y1);
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final d = sd(x + 0.5, y + 0.5);
      if (d >= 0.5) continue;
      blendPixel(dst, x, y, col, d <= -0.5 ? 1 : 0.5 - d);
    }
  }
}

void blendPixel(Img dst, int x, int y, Rgba col, double cov) {
  final a = col.a * cov / 255;
  if (a <= 0) return;
  final o = (y * dst.w + x) * 4;
  final p = dst.pix;
  final inv = 1 - a;
  p[o] = _c255(col.b * a + p[o] * inv);
  p[o + 1] = _c255(col.g * a + p[o + 1] * inv);
  p[o + 2] = _c255(col.r * a + p[o + 2] * inv);
  p[o + 3] = _c255(255 * a + p[o + 3] * inv);
}

/// Накладывает маску покрытия (например, текст) цветом col.
void blendCoverage(Img dst, Uint8List cov, int cw, int ch, int ox, int oy, Rgba col) {
  for (var y = 0; y < ch; y++) {
    final dy = oy + y;
    if (dy < 0 || dy >= dst.h) continue;
    for (var x = 0; x < cw; x++) {
      final dx = ox + x;
      if (dx < 0 || dx >= dst.w) continue;
      final c = cov[y * cw + x];
      if (c == 0) continue;
      blendPixel(dst, dx, dy, col, c / 255);
    }
  }
}

double sdRoundRect(double px, double py, double rx, double ry, double rw, double rh, double r) {
  final qx = (px - rx - rw / 2).abs() - (rw / 2 - r);
  final qy = (py - ry - rh / 2).abs() - (rh / 2 - r);
  final ox = math.max(qx, 0.0), oy = math.max(qy, 0.0);
  return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0.0) - r;
}

/// Расстояние до треугольника (максимум расстояний до прямых его сторон).
double sdTriangle(double px, double py, double ax, double ay, double bx, double by, double cx, double cy) {
  double edge(double x0, double y0, double x1, double y1, double ox, double oy) {
    final dx = x1 - x0, dy = y1 - y0;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) return -1e9;
    var d = ((px - x0) * dy - (py - y0) * dx) / len;
    // третья вершина должна быть внутри (отрицательная сторона)
    if (((ox - x0) * dy - (oy - y0) * dx) > 0) d = -d;
    return d;
  }

  return math.max(edge(ax, ay, bx, by, cx, cy), math.max(edge(bx, by, cx, cy, ax, ay), edge(cx, cy, ax, ay, bx, by)));
}

// Палитра: ночное небо и звёздный синий, под плащ звездочёта.
const colBubbleFill = Rgba(14, 20, 46, 242);
const colBubbleBorder = Rgba(77, 163, 255, 255);
const colBubbleGlow = Rgba(40, 110, 255, 60);
const colText = Rgba(232, 240, 255, 255);
const colAccent = Rgba(110, 190, 255, 255);
const colBugBar = Rgba(255, 70, 80, 255);
const colBarBack = Rgba(20, 10, 16, 200);
const colTimeBar = Rgba(255, 200, 90, 255);

/// Облачко: тело + хвостик вниз в точке tailX. Рисует только прямоугольник
/// [x0, y0, x1, y1) (по умолчанию всё): каждый пиксель считается независимо,
/// поэтому при сдвиге хвостика хватает перерисовать область вокруг него.
void drawBubble(Img dst, double bx, double by, double bw, double bh, double r, double tailX, double tailW, double tailH,
    double border,
    {int x0 = 0, int y0 = 0, int? x1, int? y1}) {
  final rx1 = x1 ?? dst.w, ry1 = y1 ?? dst.h;
  for (var y = math.max(0, y0); y < math.min(dst.h, ry1); y++) {
    final a = math.max(0, x0), b = math.min(dst.w, rx1);
    if (b > a) dst.pix.fillRange((y * dst.w + a) * 4, (y * dst.w + b) * 4, 0);
  }
  Sdf outer(double grow) => (x, y) => math.min(
        sdRoundRect(x, y, bx, by, bw, bh, r) - grow,
        sdTriangle(x, y, tailX - tailW / 2 - grow * 0.8, by + bh - 1, tailX + tailW / 2 + grow * 0.8, by + bh - 1,
            tailX - tailW * 0.15, by + bh + tailH + grow * 1.2),
      );
  double inner(double x, double y) => math.min(
        sdRoundRect(x, y, bx + border, by + border, bw - 2 * border, bh - 2 * border, math.max(1, r - border)),
        sdTriangle(x, y, tailX - tailW / 2 + border * 1.4, by + bh - border - 1, tailX + tailW / 2 - border * 1.4,
            by + bh - border - 1, tailX - tailW * 0.15, by + bh + tailH - border * 2.2),
      );
  // мягкое свечение, рамка, заливка
  fillSdf(dst, x0, y0, rx1, ry1, colBubbleGlow, outer(border + 3));
  fillSdf(dst, x0, y0, rx1, ry1, const Rgba(40, 110, 255, 90), outer(border + 1.2));
  fillSdf(dst, x0, y0, rx1, ry1, colBubbleBorder, outer(0));
  fillSdf(dst, x0, y0, rx1, ry1, Rgba(colBubbleFill.r, colBubbleFill.g, colBubbleFill.b, 255), inner);
}

void drawBar(Img dst, double x, double y, double w, double h, double frac, Rgba col) {
  final r = h / 2;
  final x0 = x.toInt() - 1, y0 = y.toInt() - 1, x1 = (x + w).toInt() + 2, y1 = (y + h).toInt() + 2;
  fillSdf(dst, x0, y0, x1, y1, colBarBack, (px, py) => sdRoundRect(px, py, x, y, w, h, r));
  if (frac <= 0) return;
  if (frac > 1) frac = 1;
  const inset = 1.5;
  final fw = (w - 2 * inset) * frac;
  if (fw < 0.5) return;
  fillSdf(
      dst,
      x0,
      y0,
      x1,
      y1,
      col,
      (px, py) =>
          sdRoundRect(px, py, x + inset, y + inset, fw, h - 2 * inset, math.max(0.5, math.min(fw / 2, r - inset))));
}
