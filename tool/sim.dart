// Симуляция поведения Dartty на фальшивом рабочем столе (работает на любой ОС).
//
//   dart run tool/sim.dart            — все сценарии
//   dart run tool/sim.dart walk jump  — только выбранные
//   dart run tool/sim.dart --snaps    — ещё и снимки в build/snaps/*.png
//
// Сценарии повторяют sim_test.go из Go-версии и проверяют новую анимацию.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartty/src/app.dart';
import 'package:dartty/src/content.dart';
import 'package:dartty/src/gfx.dart';
import 'package:dartty/src/png.dart';
import 'package:dartty/src/settings.dart';
import 'package:dartty/src/sprites.dart';
import 'package:dartty/src/world.dart';

/// Фальшивый рабочий стол 1920x1080 с панелью задач 40px и одним окном.
class FakeWorld implements World {
  double t = 0, cx = 0, cy = 0, idle = 0;
  String proc = r'C:\Program Files\Microsoft VS Code\Code.exe';
  String title = 'main.dart - app - Visual Studio Code';
  List<WinInfo> wins = [const WinInfo(101, 300, 380, 1200, 980)];
  bool quitCalled = false;
  final notified = <String>[];

  @override
  double dpi() => 1.25;
  @override
  (double, double) cursor() => (cx, cy);
  @override
  Rect4 workArea(double x, double y) => (l: 0, t: 0, r: 1920, b: 1040);
  @override
  List<WinInfo> candidateWindows() => List.of(wins);
  @override
  WinInfo? windowAlive(int h) {
    for (final x in wins) {
      if (x.h == h) return x;
    }
    return null;
  }

  @override
  int rootAt(double x, double y) {
    for (final wi in wins) {
      // первый в списке — верхний
      if (x >= wi.l && x < wi.r && y >= wi.t && y < wi.b) return wi.h;
    }
    return 0;
  }

  @override
  bool ownWindow(int h) => false;
  @override
  double idleSeconds() => idle;
  @override
  (String, String) foreground() => (proc, title);
  @override
  bool fullscreen() => false;
  @override
  void setAutostart(bool on) {}
  @override
  void notify(String title, String text) => notified.add(text);
  @override
  void quit() => quitCalled = true;

  /// Грубая имитация текста: прямоугольники вместо слов, с переносом строк.
  @override
  TextBlock renderText(String text, {required bool bold, required int px, required int maxW}) {
    final cw = px * 0.52;
    final lh = (px * 1.33).toInt();
    final words = text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final out = <(int, int, int)>[];
    var x = 0, y = 0, maxX = 0;
    for (final s in words) {
      final ww = (s.runes.length * cw).toInt();
      if (x > 0 && x + ww > maxW) {
        x = 0;
        y += lh;
      }
      out.add((x, y, ww));
      x += ww + cw.toInt();
      maxX = math.max(maxX, x);
    }
    final w = maxX + 2, h = y + lh + 2;
    final cov = Uint8List(w * h);
    for (final (ox, oy, ow) in out) {
      for (var yy = oy + lh ~/ 4; yy < oy + lh - lh ~/ 4; yy++) {
        for (var xx = ox; xx < ox + ow && xx < w; xx++) {
          cov[yy * w + xx] = 200;
        }
      }
    }
    return TextBlock(cov, w, h);
  }
}

late final SpriteBank _sharedBank;
var _snaps = false;
var _failures = 0;
var _checks = 0;

void check(bool ok, String msg) {
  _checks++;
  if (!ok) {
    _failures++;
    stdout.writeln('  ПРОВАЛ: $msg');
  }
}

(App, FakeWorld) newSim({int seed = 7}) {
  final w = FakeWorld();
  late App a;
  a = App(w, Settings(), _sharedBank, random: math.Random(seed), clock: () => w.t, save: (_) {});
  return (a, w);
}

const fps = 60.0;

void step(App a, FakeWorld w, double sec, {bool draw = true}) {
  final end = w.t + sec;
  while (w.t < end) {
    w.t += 1 / fps;
    a.frame(draw: draw);
  }
}

// ---------- Снимки ----------

/// Снимок «рабочего стола» с наложенными слоями. По умолчанию — кусок вокруг Dartty.
void snapshot(App a, FakeWorld w, String name, {bool full = false, int scale = 1}) {
  if (!_snaps) return;
  const sw = 1920, sh = 1080;
  var x0 = 0, y0 = 0, cw = sw, ch = sh;
  if (!full) {
    cw = 560;
    ch = 460;
    x0 = (a.x - cw / 2).round().clamp(0, sw - cw);
    y0 = (a.y - ch + 80).round().clamp(0, sh - ch);
  }
  final img = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final gy = y + y0, gx = x + x0;
      var r = 30 + gy ~/ 40, g = 60 + gy ~/ 30, b = 110 + gy ~/ 20;
      if (gy >= 1040) {
        r = 24;
        g = 24;
        b = 30;
      }
      for (final wi in w.wins) {
        if (gx >= wi.l && gx < wi.r && gy >= wi.t && gy < wi.b) {
          final bar = gy < wi.t + 32;
          r = bar ? 225 : 243;
          g = bar ? 228 : 243;
          b = bar ? 235 : 243;
          break;
        }
      }
      final o = (y * cw + x) * 4;
      img[o] = r;
      img[o + 1] = g;
      img[o + 2] = b;
      img[o + 3] = 255;
    }
  }
  for (final ly in [a.bugLayer, a.mascot, a.bubble]) {
    final li = ly.img;
    if (!ly.visible || li == null) continue;
    final al = ly.alpha / 255;
    for (var y = 0; y < li.h; y++) {
      for (var x = 0; x < li.w; x++) {
        final px = ly.x + x - x0, py = ly.y + y - y0;
        if (px < 0 || py < 0 || px >= cw || py >= ch) continue;
        final o = (y * li.w + x) * 4;
        final sa = li.pix[o + 3] / 255 * al;
        final d = (py * cw + px) * 4;
        img[d] = math.min(255, li.pix[o + 2] * al + img[d] * (1 - sa)).toInt();
        img[d + 1] = math.min(255, li.pix[o + 1] * al + img[d + 1] * (1 - sa)).toInt();
        img[d + 2] = math.min(255, li.pix[o] * al + img[d + 2] * (1 - sa)).toInt();
      }
    }
  }
  var outW = cw, outH = ch, out = img;
  if (scale > 1) {
    // крупный план без сглаживания, чтобы разглядеть пиксели
    outW = cw * scale;
    outH = ch * scale;
    out = Uint8List(outW * outH * 4);
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final s = ((y ~/ scale) * cw + x ~/ scale) * 4, d = (y * outW + x) * 4;
        out[d] = img[s];
        out[d + 1] = img[s + 1];
        out[d + 2] = img[s + 2];
        out[d + 3] = 255;
      }
    }
  }
  Directory('build/snaps').createSync(recursive: true);
  File('build/snaps/$name.png').writeAsBytesSync(encodePng(outW, outH, out));
}

/// Лента кадров одного слоя Dartty (для анимации): кадры подряд слева направо.
class Strip {
  final frames = <Img>[];
  final offs = <(int, int)>[];
  void add(App a) {
    final m = a.mascot.img;
    if (m == null) return;
    final c = Img(m.w, m.h)..pix.setAll(0, m.pix);
    frames.add(c);
    offs.add((a.mascot.x, a.mascot.y));
  }

  void save(String name) {
    if (!_snaps || frames.isEmpty) return;
    final fw = frames.first.w, fh = frames.first.h;
    final cols = math.min(8, frames.length), rows = (frames.length / cols).ceil();
    final w = fw * cols, h = fh * rows;
    final out = Uint8List(w * h * 4);
    for (var i = 0; i < out.length; i += 4) {
      out[i] = 40;
      out[i + 1] = 60;
      out[i + 2] = 110;
      out[i + 3] = 255;
    }
    for (var k = 0; k < frames.length; k++) {
      final f = frames[k];
      final ox = (k % cols) * fw, oy = (k ~/ cols) * fh;
      for (var y = 0; y < f.h; y++) {
        for (var x = 0; x < f.w; x++) {
          final s = (y * f.w + x) * 4, d = ((oy + y) * w + ox + x) * 4;
          final sa = f.pix[s + 3] / 255;
          out[d] = (f.pix[s + 2] + out[d] * (1 - sa)).toInt();
          out[d + 1] = (f.pix[s + 1] + out[d + 1] * (1 - sa)).toInt();
          out[d + 2] = (f.pix[s] + out[d + 2] * (1 - sa)).toInt();
        }
      }
    }
    Directory('build/snaps').createSync(recursive: true);
    File('build/snaps/$name.png').writeAsBytesSync(encodePng(w, h, out));
  }
}

// ---------- Сценарии ----------

void testEntranceAndGreeting() {
  final (a, w) = newSim();
  w.cx = 100;
  w.cy = 100;
  step(a, w, 3);
  check(a.loc == Loc.ground, 'должен приземлиться на панель задач, loc=${a.loc} y=${a.y}');
  check(a.y == 1040, 'лапы должны стоять на 1040, y=${a.y}');
  check(a.bubble.visible && a.bText.contains('Трепещи'), 'ожидалось приветствие первого запуска, текст="${a.bText}"');
  snapshot(a, w, '01_greeting');
  step(a, w, 30);
  check(a.cfg.firstRunDone, 'firstRun не отмечен');
}

void testDragThrowLandOnWindow() {
  final (a, w) = newSim();
  step(a, w, 8);
  a.onPress(a.x, a.y - 60);
  for (var i = 0; i < 60; i++) {
    w.t += 1 / fps;
    w.cx = a.pressX + i * (700 - a.pressX) / 60;
    w.cy = a.pressY + i * (200 - a.pressY) / 60;
    a.onMove(w.cx, w.cy);
    a.frame();
  }
  check(a.loc == Loc.drag, 'ожидался drag, loc=${a.loc}');
  step(a, w, 0.5);
  snapshot(a, w, '02_dragging');
  a.onRelease(w.cx, w.cy);
  step(a, w, 3);
  check(a.loc == Loc.window && a.surf == 101, 'должен сесть на окно, loc=${a.loc} surf=${a.surf} x=${a.x} y=${a.y}');
  step(a, w, 3);
  if (!a.walking && !a.emoting) check(a.pose == 'edge', 'на окне сидит на краю (edge), поза=${a.pose}');
  snapshot(a, w, '03_on_window');
  // окно сдвигается — Dartty едет вместе с ним
  w.wins[0] = w.wins[0].moved(dx: 100, dy: -50);
  final x0 = a.x;
  step(a, w, 0.5);
  check(!((a.x - (x0 + 100)).abs() > 1 && !a.walking) && a.y == w.wins[0].t,
      'не поехал с окном: x=${a.x} (было $x0) y=${a.y} T=${w.wins[0].t}');
  // окно закрыли — падает на панель задач
  w.wins = [];
  step(a, w, 3);
  check(a.loc == Loc.ground, 'должен упасть на землю, loc=${a.loc}');
}

void testBugBattleWin() {
  final (a, w) = newSim();
  step(a, w, 40);
  final xp0 = a.cfg.xp;
  a.summonBug(training: true);
  step(a, w, 1.5);
  snapshot(a, w, '04_bug_fight', full: true);
  check(a.bug == BugState.fight && a.bugLayer.visible, 'Баг не появился');
  for (var i = 0; i < 7; i++) {
    a.onBugClick();
    step(a, w, 0.2);
    if (i == 3) snapshot(a, w, '05_bug_hit', full: true);
  }
  check(a.bug == BugState.win, 'Баг должен быть побеждён, state=${a.bug} hp=${a.bugHP}');
  step(a, w, 0.3);
  check(a.pose == 'proud', 'после победы гордится, поза=${a.pose}');
  snapshot(a, w, '06_bug_win', full: true);
  step(a, w, 3);
  check(a.bug == BugState.none && a.cfg.bugsDefeated == 1 && a.cfg.xp == xp0 + 5,
      'после победы: bug=${a.bug} defeated=${a.cfg.bugsDefeated} xp=${a.cfg.xp}');
}

void testBugBattleLose() {
  final (a, w) = newSim();
  step(a, w, 40);
  a.summonBug(training: false);
  step(a, w, 12);
  check(a.bug == BugState.none && a.cfg.bugsEscaped == 1,
      'Баг должен сбежать: bug=${a.bug} escaped=${a.cfg.bugsEscaped}');
}

void testPomodoro() {
  final (a, w) = newSim();
  step(a, w, 40);
  a.startPomodoro();
  step(a, w, 60);
  check(a.pose == 'focused' || a.emote.isNotEmpty || a.loc == Loc.window,
      'в фокусе должен сидеть сосредоточенно, поза=${a.pose}');
  check(!a.walking, 'в фокусе не гуляет');
  step(a, w, 25 * 60, draw: false);
  check(a.pomo == Pomo.rest, 'после 25 минут — перерыв, pomo=${a.pomo}');
  step(a, w, 5 * 60 + 2, draw: false);
  check(a.pomo == Pomo.off && a.pomoOffer != 0, 'после перерыва — предложение нового помодоро, pomo=${a.pomo}');
  a.onPress(a.x, a.y - 50);
  a.onRelease(a.x, a.y - 50);
  check(a.pomo == Pomo.focus, 'клик после перерыва должен запустить новый помодоро');
}

void testTipAndStatsBubble() {
  final (a, w) = newSim();
  step(a, w, 60);
  a.showTip();
  step(a, w, 0.5);
  snapshot(a, w, '07_tip');
  check(a.bHeader.isNotEmpty, 'у совета должен быть заголовок');
  a.showStats();
  check(a.bText.contains('Уровень 1') && !a.bText.contains('{'), 'статистика с подстановками: "${a.bText}"');
}

/// Долгая жизнь: 6 виртуальных часов с переключением программ и перерывами.
void testLongLife() {
  final (a, w) = newSim();
  final r = math.Random(3);
  final said = <String, int>{};
  final poses = <String, int>{};
  var lastText = '';
  const apps = [
    (r'C:\VS Code\Code.exe', 'main.dart - Visual Studio Code'),
    (r'C:\Android Studio\bin\studio64.exe', 'my_app – main.dart'),
    (r'C:\Chrome\chrome.exe', 'YouTube - Google Chrome'),
    (r'C:\Chrome\chrome.exe', 'pub.dev - Google Chrome'),
    (r'C:\Chrome\chrome.exe', 'Новости - Google Chrome'),
    (r'C:\Telegram\Telegram.exe', 'Telegram'),
    (r'C:\Windows\System32\WindowsTerminal.exe', 'flutter run'),
  ];
  var cur = 0;
  var nextSwitch = 0.0, idleUntil = 0.0;
  var maxY = 0.0, minY = 1e9, airTime = 0.0;
  var frame = 0;
  var escaped = false;
  final sw = Stopwatch()..start();
  while (w.t < 6 * 3600) {
    w.t += 1 / 30;
    frame++;
    if (w.t > nextSwitch) {
      cur = r.nextInt(apps.length);
      nextSwitch = w.t + 60 + r.nextDouble() * 900;
      if (r.nextDouble() < 0.08) idleUntil = w.t + 200 + r.nextDouble() * 600;
    }
    final (proc, title) = apps[cur];
    w.proc = proc;
    w.title = title;
    if (w.t < idleUntil) {
      w.idle += 1 / 30;
    } else {
      w.idle = 0.5;
      w.cx = 960 + 900 * math.sin(w.t * 0.05);
      w.cy = 540 + 400 * math.cos(w.t * 0.07);
    }
    // иногда кликаем Бага, если он есть
    if (a.bug == BugState.fight && r.nextDouble() < 0.02) a.onBugClick();
    a.frame(draw: frame % 15 == 0); // пиксели — раз в полсекунды, логика — каждый кадр
    if (a.bText != lastText && a.bText.isNotEmpty) {
      lastText = a.bText;
      final k = a.bText.runes.length > 40 ? String.fromCharCodes(a.bText.runes.take(40)) : a.bText;
      said[k] = (said[k] ?? 0) + 1;
    }
    if (a.mascot.visible) poses[a.pose] = (poses[a.pose] ?? 0) + 1;
    if (a.loc == Loc.air) airTime += 1 / 30;
    maxY = math.max(maxY, a.y);
    minY = math.min(minY, a.y);
    if (!escaped && (a.x < 0 || a.x > 1920 || a.x.isNaN || a.y.isNaN)) {
      escaped = true;
      check(false, 'Dartty убежал с экрана: x=${a.x} y=${a.y} t=${w.t}');
    }
  }
  check(maxY <= 1040.5, 'провалился под панель задач: maxY=$maxY');
  check(airTime <= 120, 'слишком долго в воздухе: ${airTime.toStringAsFixed(0)} с');
  final li = levelInfo(a.cfg.xp);
  stdout.writeln(
      '  XP=${a.cfg.xp} уровень ${li.level} (${li.title}), код ${(a.cfg.codingSeconds / 60).toStringAsFixed(0)} мин, '
      'багов: побеждено ${a.cfg.bugsDefeated}, сбежало ${a.cfg.bugsEscaped}; ${sw.elapsedMilliseconds} мс');
  final ps = poses.entries.toList()..sort((x, y) => y.value - x.value);
  stdout.writeln('  позы: ${ps.map((e) => '${e.key}=${e.value}').join(', ')}');
  stdout.writeln('  разных реплик: ${said.length}');
  check(a.cfg.xp >= 60, 'опыт почти не растёт');
  for (final p in ['walk', 'side', 'edge', 'sleep', 'idle']) {
    check(poses.containsKey(p), 'за 6 часов ни разу не было позы $p');
  }
}

void testRenderPoses() {
  final (a, w) = newSim();
  w.cx = 50;
  w.cy = 50;
  step(a, w, 5);
  a.bUntil = 0;
  step(a, w, 1);
  final strip = Strip();
  for (final p in [
    'idle', 'excited', 'pathos', 'focused', 'curious', 'sleep', 'offended', 'scared', 'angry', 'sad', //
    'blink', 'wave', 'yawn', 'proud', 'edge', 'side'
  ]) {
    a.setEmote(p, 5);
    step(a, w, 0.4);
    check(a.pose == p, 'поза $p не показана (${a.pose})');
    snapshot(a, w, 'pose_$p');
    strip.add(a);
  }
  strip.save('poses_strip');
}

/// Ходьба: поворот боком, плавный разгон, шаги по пройденному пути, торможение.
void testWalk() {
  final (a, w) = newSim();
  w.cx = 50;
  w.cy = 50;
  step(a, w, 4);
  a.bUntil = 0;
  var guard = 0.0;
  while (!a.walking && guard < 120) {
    step(a, w, 1 / fps);
    guard += 1 / fps;
  }
  check(a.walking, 'за 2 минуты так и не пошёл гулять');
  if (!a.walking) return;
  check(a.pose == 'side' && a.walkPhase == WalkPhase.turn, 'перед ходьбой поворачивается боком, поза=${a.pose}');
  final strip = Strip();
  final vels = <double>[];
  var x0 = a.x;
  var sawWalk = false, maxStep = 0.0, maxJerk = 0.0, prevStep = 0.0;
  for (var i = 0; i < 90; i++) {
    final px = a.x;
    step(a, w, 1 / fps);
    final d = (a.x - px).abs();
    if (i > 0) maxJerk = math.max(maxJerk, (d - prevStep).abs());
    prevStep = d;
    maxStep = math.max(maxStep, d);
    vels.add(a.walkVel);
    if (a.pose == 'walk') sawWalk = true;
    if (i % 3 == 0 && i < 72) strip.add(a);
  }
  strip.save('walk_strip');
  check(sawWalk, 'поза walk не появилась');
  check(vels.first < a.walkSpeed * 0.2, 'стартует не с места: v0=${vels.first}');
  check(vels.any((v) => v > 0 && v < a.walkSpeed * 0.9), 'нет плавного разгона');
  // ускорение ограничено: за кадр скорость меняется не больше чем на speed/rampDur/60
  check(maxJerk <= a.walkSpeed / 0.25 / fps / fps + 0.01, 'рывок скорости: $maxJerk px/кадр');
  stdout.writeln('  шаг за кадр до ${maxStep.toStringAsFixed(2)} px, путь ${(a.x - x0).abs().toStringAsFixed(0)} px');
  x0 = a.x;
  // дождёмся остановки: скорость должна плавно упасть до нуля
  final stopVels = <double>[];
  guard = 0;
  while (a.walking && guard < 12) {
    step(a, w, 1 / fps);
    stopVels.add(a.walkVel);
    guard += 1 / fps;
  }
  check(!a.walking, 'не остановился за 12 с');
  final decel = stopVels.where((v) => v > 0 && v < a.walkSpeed * 0.9).length;
  check(decel >= 6, 'торможение слишком резкое: $decel кадров');
  step(a, w, 0.3);
  check(a.pose == 'idle' || a.pose == 'curious' || a.emoting, 'после ходьбы стоит, поза=${a.pose}');
}

/// Прыжок на окно: присед → полёт с растяжением → приземление на edge с пружинным сжатием.
void testJumpToWindow() {
  final (a, w) = newSim();
  w.cx = 50;
  w.cy = 50;
  step(a, w, 4);
  a.bUntil = 0;
  a.x = 700;
  step(a, w, 0.1);
  var ok = false;
  for (var i = 0; i < 50 && !ok; i++) {
    ok = a.tryHopToWindow();
  }
  check(ok, 'не нашёл окно для прыжка');
  if (!ok) return;
  final strip = Strip();
  var minSy = 9.0, maxSy = 0.0, landed = -1.0, minAfter = 9.0, maxAfter = 0.0;
  var sawPrep = false;
  for (var i = 0; i < 120; i++) {
    step(a, w, 1 / fps);
    if (a.loc == Loc.jump && a.now < a.jPrep) sawPrep = true;
    final sy = a.anim.sy.value * a.anim.squash.value;
    minSy = math.min(minSy, sy);
    maxSy = math.max(maxSy, sy);
    if (landed < 0 && a.loc == Loc.window) landed = a.now;
    if (landed >= 0) {
      minAfter = math.min(minAfter, a.anim.squash.value);
      maxAfter = math.max(maxAfter, a.anim.squash.value);
    }
    if (i % 4 == 0 && i < 64) strip.add(a);
  }
  strip.save('jump_strip');
  check(sawPrep, 'нет приседа перед прыжком');
  check(maxSy > 1.03, 'нет растяжения в полёте: max sy=$maxSy');
  check(landed >= 0 && a.loc == Loc.window, 'не приземлился на окно, loc=${a.loc}');
  check(a.emote != 'scared', 'после своего прыжка не пугается, как при падении');
  check(minAfter < 0.95 && maxAfter > 1.0, 'нет пружинного сжатия с отскоком: min=$minAfter max=$maxAfter');
  step(a, w, 3);
  if (!a.walking && !a.emoting) check(a.pose == 'edge', 'на окне поза edge, а не ${a.pose}');
  snapshot(a, w, '08_edge_after_jump', scale: 1);
}

/// Окно, на котором сидит Dartty, перекрыли другим: падает сразу, а не через пару секунд.
void testCoveredWindow() {
  final (a, w) = newSim();
  a.cfg.walk = false;
  w.cx = 50;
  w.cy = 50;
  step(a, w, 4);
  a.x = 700;
  step(a, w, 0.1);
  var ok = false;
  for (var i = 0; i < 50 && !ok; i++) {
    ok = a.tryHopToWindow();
  }
  step(a, w, 3);
  check(a.loc == Loc.window, 'не сел на окно, loc=${a.loc}');
  if (a.loc != Loc.window) return;
  // окно в стороне не мешает
  w.wins.insert(0, WinInfo(102, a.x + 200, 100, a.x + 600, 900));
  step(a, w, 1.5);
  check(a.loc == Loc.window, 'упал, хотя окно сверху лежит в стороне, loc=${a.loc}');
  // а это окно активировали, и оно закрыло место под Dartty
  w.wins[0] = WinInfo(102, a.x - 300, 100, a.x + 300, 900);
  final t0 = w.t;
  var fellAt = -1.0;
  while (w.t - t0 < 3 && fellAt < 0) {
    step(a, w, 1 / fps);
    if (a.loc != Loc.window) fellAt = w.t - t0;
  }
  stdout.writeln('  начал падать через ${(fellAt * 1000).round()} мс');
  check(fellAt >= 0 && fellAt <= 0.5,
      'после перекрытия окна должен упасть за 0,5 с, а не через ${fellAt.toStringAsFixed(2)} с');
  step(a, w, 3);
  check(a.loc == Loc.ground || a.loc == Loc.window, 'должен приземлиться, loc=${a.loc}');
}

/// Моргание каждые 3–6 с по 90–130 мс; плавная смена поз.
void testBlinkAndCrossfade() {
  final (a, w) = newSim(seed: 11);
  a.cfg.walk = false;
  a.cfg.windowHop = false;
  w.cx = 50;
  w.cy = 50;
  step(a, w, 5);
  a.bUntil = 0;
  var blinks = 0, longest = 0, run = 0;
  for (var i = 0; i < 30 * fps; i++) {
    step(a, w, 1 / fps);
    final f = a.anim.frame(a.s, 0, 0);
    if (f.blink) {
      if (run == 0) blinks++;
      run++;
      longest = math.max(longest, run);
    } else {
      run = 0;
    }
  }
  stdout.writeln('  морганий за 30 с: $blinks, самое долгое ${(longest / fps * 1000).round()} мс');
  check(blinks >= 5 && blinks <= 14, 'морганий за 30 с должно быть 5–14, а не $blinks');
  check(longest <= 9, 'моргание слишком долгое: $longest кадров');

  // кроссфейд: в первые 150 мс после смены позы видны обе позы
  a.setEmote('excited', 1);
  final fades = <double>[];
  final strip = Strip();
  for (var i = 0; i < 14; i++) {
    step(a, w, 1 / fps);
    fades.add(a.anim.fade);
    strip.add(a);
  }
  strip.save('crossfade_strip');
  check(fades.first < 0.3 && fades.any((f) => f > 0.3 && f < 0.9) && fades.last >= 1,
      'кроссфейд за ~150 мс: ${fades.map((f) => f.toStringAsFixed(2)).join(' ')}');
}

/// В покое Dartty перерисовывается редко и быстро (бюджет CPU 1–2%).
void testIdleCost() {
  final (a, w) = newSim(seed: 5);
  a.cfg.walk = false;
  a.cfg.windowHop = false;
  a.cfg.chatter = false;
  w.cx = 50;
  w.cy = 50;
  step(a, w, 6);
  a.bUntil = 0;
  step(a, w, 2);
  var renders = 0;
  var lastKey = a.renderKey;
  final sw = Stopwatch()..start();
  for (var i = 0; i < 20 * fps; i++) {
    w.t += 1 / fps;
    a.frame();
    if (a.renderKey != lastKey) {
      renders++;
      lastKey = a.renderKey;
    }
  }
  final ms = sw.elapsedMicroseconds / 1000;
  final perSec = renders / 20;
  final cpu = ms / 20 / 10; // мс в секунду → % одного ядра
  stdout.writeln('  в покое: ${perSec.toStringAsFixed(1)} перерисовок/с, '
      '${(ms / renders).toStringAsFixed(2)} мс на кадр, ≈${cpu.toStringAsFixed(2)}% ядра (без Win32)');
  check(perSec <= 25, 'слишком частая перерисовка в покое: $perSec/с');
  check(cpu < 2, 'в покое слишком дорого: ${cpu.toStringAsFixed(2)}%');

  // а при ходьбе — сколько стоит кадр
  a.cfg.walk = true;
  var t = 0.0;
  while (!a.walking && t < 200) {
    step(a, w, 0.1, draw: false);
    t += 0.1;
  }
  step(a, w, 0.5);
  final sw2 = Stopwatch()..start();
  var n = 0;
  while (a.walking && n < 120) {
    w.t += 1 / fps;
    a.frame();
    n++;
  }
  if (n > 0) stdout.writeln('  при ходьбе: ${(sw2.elapsedMicroseconds / 1000 / n).toStringAsFixed(2)} мс на кадр');
}

void testContent() {
  const banned = [
    'Сила',
    'Силе',
    'Силу',
    'Силой',
    'галактик',
    'лорд',
    'шлем',
    'тёмной сторон',
    'тёмная сторона',
    'Империя',
    'джедай',
    'ситх'
  ];
  for (final e in phrases.entries) {
    for (final p in e.value) {
      for (final b in banned) {
        final hit = b.startsWith('Сил') ? p.contains(b) : p.toLowerCase().contains(b.toLowerCase());
        check(!hit, 'в реплике ${e.key} осталось «$b»: $p');
      }
    }
  }
  for (final t in levelTitles) {
    check(!t.contains('Лорд') && !t.contains('Император'), 'титул из старого персонажа: $t');
  }
  // совместимость настроек с Go-версией
  final s =
      Settings.fromJson({'size': 0, 'xp': 34, 'codingSeconds': 870, 'posX': 542.28, 'hasPos': true, 'bugsDefeated': 4});
  final j = s.toJson();
  check(j['xp'] == 34 && j['size'] == 0 && j['posX'] == 542.28 && j['codingSeconds'] == 870.0, 'настройки не читаются');
  check(j.length == 27, 'в настройках должно быть 27 ключей, как в Go, а не ${j.length}');
}

void main(List<String> args) {
  _snaps = args.contains('--snaps');
  final only = args.where((a) => !a.startsWith('--')).toSet();
  final files = <String, Uint8List>{};
  for (final n in spriteNames) {
    files[n] = File('assets/sprites/$n.png').readAsBytesSync();
  }
  final sw = Stopwatch()..start();
  _sharedBank = SpriteBank.fromPng(files);
  stdout.writeln('спрайты: ${files.length} шт. за ${sw.elapsedMilliseconds} мс');

  final tests = <String, void Function()>{
    'entrance': testEntranceAndGreeting,
    'drag': testDragThrowLandOnWindow,
    'bugwin': testBugBattleWin,
    'buglose': testBugBattleLose,
    'pomodoro': testPomodoro,
    'tip': testTipAndStatsBubble,
    'poses': testRenderPoses,
    'walk': testWalk,
    'jump': testJumpToWindow,
    'cover': testCoveredWindow,
    'blink': testBlinkAndCrossfade,
    'idlecost': testIdleCost,
    'content': testContent,
    'life': testLongLife,
  };
  for (final e in tests.entries) {
    if (only.isNotEmpty && !only.contains(e.key)) continue;
    final before = _failures;
    final t = Stopwatch()..start();
    stdout.writeln('▶ ${e.key}');
    e.value();
    stdout.writeln('  ${_failures == before ? 'ok' : 'ПРОВАЛЕНО'} (${t.elapsedMilliseconds} мс)');
  }
  stdout.writeln(
      _failures == 0 ? 'Симуляция пройдена: $_checks проверок.' : 'Провалено проверок: $_failures из $_checks.');
  exit(_failures == 0 ? 0 : 1);
}
