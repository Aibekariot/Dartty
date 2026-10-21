// Мозг Dartty: движение, эмоции, реплики, напоминания, помодоро, опыт и битвы с Багом.
// Этот файл не зависит от Windows — всё общение с системой идёт через World.

import 'dart:math' as math;

import 'anim.dart';
import 'content.dart';
import 'gfx.dart';
import 'settings.dart';
import 'sprites.dart';
import 'world.dart';

enum Loc { ground, window, air, drag, jump }

enum Pomo { off, focus, rest }

enum BugState { none, fight, win, lose }

enum WalkPhase { turn, move, stop }

class _Msg {
  final String text, header;
  final int prio;
  final double dur;
  const _Msg(this.text, this.header, this.prio, this.dur);
}

/// Сколько секунд Dartty поворачивается боком перед ходьбой и разгоняется.
const _turnDur = 0.2, _rampDur = 0.25;

class App {
  final World w;
  final Settings cfg;
  final SpriteBank bank;
  final math.Random rnd;
  final double Function()? _clockFn;
  final void Function(Settings) _save;
  final _watch = Stopwatch()..start();

  late final MascotAnimator anim = MascotAnimator(rnd);
  late final MascotRenderer renderer = MascotRenderer(bank);
  final _intent = MascotIntent();

  double now = 0;
  double u = 1; // масштаб интерфейса (DPI)
  double s = 1; // масштаб спрайтов
  int wc = 1, hc = 1;
  double footY = 0, halfW = 0;
  double quitAt = 0;
  bool hidden = false, fsHidden = false;
  double secAcc = 0, _warmAt = 0;

  // питомец
  double x = 0, y = 0, vx = 0, vy = 0;
  Loc loc = Loc.air;
  int surf = 0;
  double surfRel = 0;
  int surfMissCount = 0;
  double surfCheckAt = 0;
  double facing = 1;
  bool walking = false;
  WalkPhase walkPhase = WalkPhase.turn;
  double walkT0 = 0, walkEnd = 0, walkSpeed = 0, walkVel = 0, walkDist = 0;
  double nextDecide = 0;
  String emote = '';
  double emoteStart = 0, emoteEnd = 0;
  bool sleeping = false;
  List<WinInfo> fallCands = [];
  double fallStartY = 0;
  bool longDrag = false;
  double jx0 = 0, jy0 = 0, jx1 = 0, jy1 = 0;
  double jT0 = 0, jDur = 0, jH = 0, jPrep = 0;
  int jSurf = 0;
  double jSurfL = 0, jSurfT = 0;
  bool pressed = false, dragging = false;
  double pressX = 0, pressY = 0, grabDX = 0, grabDY = 0, dragStart = 0;
  double lastCX = 0, lastCY = 0, dvx = 0, dvy = 0, lastMoveT = 0;
  final clicks = <double>[];
  double curiousSince = 0, curiousBlockTil = 0;
  bool entranceDone = false;
  String pose = 'idle';

  // рендер
  final mascot = Layer();
  String renderKey = '';
  final bubble = Layer();
  String bubbleKey = '';
  final bugLayer = Layer();
  String bugKey = '';

  // облачко
  String bText = '', bHeader = '';
  double bUntil = 0;
  int bPrio = 0;
  final bQueue = <_Msg>[];
  double bGapUntil = 0;
  Img? bubbleImg, _bubbleBase;
  double bubbleTailX = 0;
  TextBlock _bHead = TextBlock.empty, _bBody = TextBlock.empty;
  double _bMar = 0, _bW = 0, _bH = 0, _bPad = 0, _bGap = 0;

  // таймеры
  Pomo pomo = Pomo.off;
  double pomoEnd = 0;
  int pomoCycle = 0;
  double pomoOffer = 0;
  double waterAcc = 0, sitAcc = 0, nextNight = 0, nextChatter = 0;
  double bugAcc = 0, bugNeed = 0, codingMinAcc = 0, codingHourAcc = 0;
  double tipAt = 0, saveAt = 0;

  // реакции на программы
  String curCat = '';
  double catSince = 0, lastIdeSeen = 0;
  double browseAcc = 0, ytAcc = 0, msgAcc = 0;
  final cool = <String, double>{};
  String lastTitle = '';

  // Баг
  BugState bug = BugState.none;
  double bugX = 0, bugY = 0, bugFX = 0, bugFY = 0, bugTX = 0, bugTY = 0;
  double bugMoveT0 = 0, bugMoveDur = 0, bugNextMove = 0;
  int bugHP = 0, bugMaxHP = 7;
  double bugStart = 0, bugEnd = 0, bugFlash = 0, bugFacing = 1;
  bool bugDashing = false;
  double bugPhaseAt = 0, bugVY = 0;

  final _bags = <String, List<int>>{};

  /// Счётчики для `--stats`: сколько раз и сколько микросекунд рисовался Dartty.
  int statRenders = 0, statRenderUs = 0;
  final _statWatch = Stopwatch();

  App(this.w, this.cfg, this.bank, {math.Random? random, double Function()? clock, void Function(Settings)? save})
      : rnd = random ?? math.Random(),
        _clockFn = clock,
        _save = save ?? saveSettings {
    u = w.dpi();
    rescale();
    loc = Loc.air;
    var wa = w.workArea(0, 0);
    x = wa.r - 220 * u;
    if (cfg.hasPos) {
      final p = w.workArea(cfg.posX, cfg.posY);
      if (cfg.posX > p.l && cfg.posX < p.r) {
        x = cfg.posX;
        wa = p;
      }
    }
    y = wa.t - 40 * u;
    vy = 0;
    fallStartY = y;
    nextDecide = 6;
    nextChatter = randf(6 * 60, 11 * 60);
    bugNeed = randf(14 * 60, 22 * 60);
    nextNight = 90;
    saveAt = 300;
    mascot.visible = true;
  }

  double randf(double lo, double hi) => lo + rnd.nextDouble() * (hi - lo);

  void rescale() {
    s = sizeFactors[cfg.size] * u;
    bank.clear();
    wc = (360 * s * 1.24).ceil() + 8;
    footY = (footLine * s * 1.16).ceil() + 6;
    hc = (footY + (80 * s * 1.15).ceil() + 6).toInt();
    halfW = 130 * s;
    renderKey = '';
    bubbleKey = '';
    bugKey = '';
  }

  // ---------- Реплики ----------

  String pick(String key) {
    final list = phrases[key];
    if (list == null || list.isEmpty) return '';
    var bag = _bags[key];
    if (bag == null || bag.isEmpty) bag = List<int>.generate(list.length, (i) => i)..shuffle(rnd);
    final i = bag.removeAt(0);
    _bags[key] = bag;
    return list[i];
  }

  /// prio: 0 — болтовня, 1 — реакция, 2 — важное (напоминание), 3 — системное/по запросу.
  void say(String text, int prio) => sayFull(text, '', prio, 0);

  static double _autoDur(String text) => math.max(3.2, math.min(11, 2.4 + 0.06 * text.runes.length));

  void sayFull(String text, String header, int prio, double dur) {
    if (text.isEmpty) return;
    if (cfg.dnd && prio < 3) return;
    if ((hidden || fsHidden) && prio < 3) return;
    if (dur == 0) dur = _autoDur(text + header);
    final m = _Msg(text, header, prio, dur);
    if (bText.isNotEmpty && now < bUntil && bPrio > prio) {
      if (bQueue.length < 4) bQueue.add(m);
      return;
    }
    _showBubble(m);
  }

  void queueSay(String text, int prio) {
    if (bText.isNotEmpty && now < bUntil) {
      bQueue.add(_Msg(text, '', prio, _autoDur(text)));
      return;
    }
    say(text, prio);
  }

  void _showBubble(_Msg m) {
    bText = m.text;
    bHeader = m.header;
    bPrio = m.prio;
    bUntil = now + m.dur;
    bubbleKey = '';
    bubbleImg = null;
  }

  void dismissBubble() => bUntil = now;

  // ---------- Эмоции ----------

  void setEmote(String p, double dur) {
    emote = p;
    emoteStart = now;
    emoteEnd = now + dur;
  }

  bool get emoting => emote.isNotEmpty && now < emoteEnd;

  void stopWalk() {
    walking = false;
    walkVel = 0;
  }

  // ---------- Ввод ----------

  double clock() => _clockFn != null ? _clockFn() : _watch.elapsedMicroseconds / 1e6;

  void onPress(double cx, double cy) {
    now = math.max(now, clock());
    pressed = true;
    dragging = false;
    pressX = cx;
    pressY = cy;
    grabDX = x - cx;
    grabDY = y - cy;
    lastCX = cx;
    lastCY = cy;
    lastMoveT = now;
    dvx = dvy = 0;
  }

  void onMove(double cx, double cy) {
    if (!pressed) return;
    now = math.max(now, clock());
    if (!dragging) {
      if (math.sqrt((cx - pressX) * (cx - pressX) + (cy - pressY) * (cy - pressY)) < 6 * u) return;
      dragging = true;
      loc = Loc.drag;
      stopWalk();
      sleeping = false;
      emote = '';
      surf = 0;
      dragStart = now;
    }
    final dt = now - lastMoveT;
    if (dt > 0.001) {
      final k = math.min(1.0, dt * 12);
      dvx += ((cx - lastCX) / dt - dvx) * k;
      dvy += ((cy - lastCY) / dt - dvy) * k;
    }
    lastCX = cx;
    lastCY = cy;
    lastMoveT = now;
    x = cx + grabDX;
    y = cy + grabDY;
  }

  void onRelease(double cx, double cy) {
    if (!pressed) return;
    pressed = false;
    if (dragging) {
      dragging = false;
      longDrag = now - dragStart > 3;
      if (now - lastMoveT > 0.08) dvx = dvy = 0;
      final lim = 2200 * u;
      vx = dvx.clamp(-lim, lim);
      vy = dvy.clamp(-lim, lim);
      startFall();
      return;
    }
    _onClick();
  }

  void startFall() {
    loc = Loc.air;
    surf = 0;
    fallStartY = y;
    fallCands = cfg.windowHop ? w.candidateWindows() : [];
  }

  void _onClick() {
    clicks.add(now);
    clicks.removeWhere((t) => now - t >= 2.2);
    curiousBlockTil = now + 3;
    if (bug == BugState.fight) {
      setEmote('scared', 0.6);
      say('Не меня! Бей Бага!', 1);
      return;
    }
    if (clicks.length >= 5) {
      clicks.clear();
      if (rnd.nextInt(2) == 0) {
        setEmote('angry', 1.8);
      } else {
        setEmote('scared', 1.4);
      }
      say(pick('clickSpam'), 1);
      return;
    }
    if (sleeping) {
      sleeping = false;
      setEmote('scared', 0.8);
      say(pick('wake'), 1);
      return;
    }
    if (pomo == Pomo.focus) {
      final left = ((pomoEnd - now) / 60).ceil();
      setEmote('focused', 1.5);
      say(fill(pick('pomoClick'), {'n': left}), 3);
      return;
    }
    if (pomo == Pomo.rest) {
      final left = ((pomoEnd - now) / 60).ceil();
      setEmote('excited', 1.2);
      say(fill(pick('breakClick'), {'n': left}), 3);
      return;
    }
    if (pomoOffer > now) {
      pomoOffer = 0;
      startPomodoro();
      return;
    }
    // «blink» — довольно зажмурился: его погладили.
    const poses = ['excited', 'pathos', 'blink', 'curious', 'excited', 'blink'];
    setEmote(poses[rnd.nextInt(poses.length)], 1.6);
    say(pick('click'), 1);
  }

  void onBugClick() {
    if (bug != BugState.fight) return;
    bugHP--;
    bugFlash = now + 0.13;
    setEmote('pathos', 0.35);
    if (bugHP <= 0) {
      bug = BugState.win;
      bugPhaseAt = now;
      bugEnd = now + 1.5;
      cfg.bugsDefeated++;
      _addXP(5);
      setEmote('proud', 2.6);
      bugVY = -250 * u;
      sayFull(pick('bugWin'), '', 3, 3.5);
      return;
    }
    // после удара Баг отскакивает
    bugNextMove = now + 0.05;
  }

  // ---------- Действия из меню ----------

  void startPomodoro() {
    pomo = Pomo.focus;
    pomoEnd = now + cfg.pomoFocus * 60;
    stopWalk();
    setEmote('pathos', 1.5);
    say(pick('pomoStart'), 3);
  }

  void stopPomodoro() {
    pomo = Pomo.off;
    pomoCycle = 0;
    say(pick('pomoStop'), 3);
  }

  String _nextTip() {
    cfg.tipIndex = cfg.tipIndex % tips.length;
    final tip = tips[cfg.tipIndex];
    cfg.tipIndex = (cfg.tipIndex + 1) % tips.length;
    return tip;
  }

  void showTip() {
    final tip = _nextTip();
    setEmote('pathos', 1.4);
    sayFull(tip, 'Совет звездочёта', 3, math.max(8, math.min(16, 3 + 0.07 * tip.runes.length)));
  }

  void showStats() {
    final li = levelInfo(cfg.xp);
    setEmote('proud', 1.6);
    say(fill(pick('stats'), {'level': li.level, 'title': li.title, 'xp': li.need - li.into, 'bugs': cfg.bugsDefeated}),
        3);
  }

  void summonBug({required bool training}) {
    if (bug != BugState.none || hidden || fsHidden) return;
    if (training) say(pick('bugTraining'), 3);
    _spawnBug();
  }

  void setHidden(bool h) {
    if (hidden == h) return;
    hidden = h;
    if (!h) {
      setEmote('wave', 1.8);
      say(pick('unhide'), 3);
    } else {
      bUntil = now;
      bug = BugState.none;
    }
  }

  void setSize(int i) {
    if (i == cfg.size) return;
    final up = i > cfg.size;
    cfg.size = i;
    rescale();
    if (up) {
      setEmote('pathos', 1.5);
      say(pick('sizeUp'), 3);
    } else {
      setEmote('excited', 1.2);
      say(pick('sizeDown'), 3);
    }
  }

  void setDND(bool on) {
    if (on) {
      say(pick('dndOn'), 3);
      cfg.dnd = true;
      if (bug == BugState.fight) bug = BugState.none;
    } else {
      cfg.dnd = false;
      setEmote('excited', 1.2);
      say(pick('dndOff'), 3);
    }
  }

  void setClickThrough(bool on) {
    cfg.clickThrough = on;
    say(pick(on ? 'ghostOn' : 'ghostOff'), 3);
  }

  void setAutostart(bool on) {
    cfg.autostart = on;
    w.setAutostart(on);
    if (on) say(pick('autostartOn'), 3);
  }

  void setWalk(bool on) {
    cfg.walk = on;
    if (!on) stopWalk();
  }

  void requestQuit() {
    if (quitAt > 0) return;
    hidden = false;
    setEmote('sad', 3);
    say(phrases['quit']![0], 3);
    quitAt = now + 1.7;
  }

  (Pomo, double) pomoState() => (pomo, math.max(0, pomoEnd - now));

  // ---------- Опыт ----------

  void _addXP(int n) {
    final before = levelInfo(cfg.xp).level;
    cfg.xp += n;
    final after = levelInfo(cfg.xp);
    if (after.level > before) {
      setEmote('proud', 3);
      say(fill(pick('levelUp'), {'title': after.title}), 2);
    }
  }

  // ---------- Главный цикл ----------

  /// Вызывается ~60 раз в секунду. [draw]: false — только логика, без пикселей.
  void frame({bool draw = true}) {
    final t = clock();
    final dt = (t - now).clamp(0.0, 0.1);
    now = t;

    if (quitAt > 0 && now >= quitAt) w.quit();

    secAcc += dt;
    while (secAcc >= 1) {
      secAcc -= 1;
      _second();
    }

    if (!hidden && !fsHidden) {
      _physics(dt);
      _updateBug(dt);
    }
    _updateBubbleQueue();
    _updatePose(dt);
    _renderMascot(draw);
    _renderBubble(draw);
    _renderBug(draw);
    if (draw && !busy && now - _warmAt > 0.05) {
      _warmAt = now;
      // Заранее уменьшаем спрайты по одному за кадр, чтобы смена позы не тормозила.
      if (!bank.warmOne(spriteNames.where((n) => !n.startsWith('bug_')), s)) {
        bank.warmOne(spriteNames.where((n) => n.startsWith('bug_')), _bugScale);
      }
    }
  }

  Rect4 _groundAt(double x, double y) => w.workArea(x, y - 20 * u);

  bool get busy => dragging || loc == Loc.air || loc == Loc.jump || loc == Loc.drag;

  void _physics(double dt) {
    if (walking && emoting) {
      // эмоция важнее прогулки: останавливаемся, а не скользим
      stopWalk();
      nextDecide = now + randf(3, 6);
    }
    switch (loc) {
      case Loc.drag:
        return;
      case Loc.air:
        final g = 2600 * u;
        vy += g * dt;
        vx *= math.pow(0.6, dt);
        final prevY = y;
        x += vx * dt;
        y += vy * dt;
        final ga = _groundAt(x, prevY);
        if (x < ga.l + halfW) {
          x = ga.l + halfW;
          vx = vx.abs() * 0.5;
        }
        if (x > ga.r - halfW) {
          x = ga.r - halfW;
          vx = -vx.abs() * 0.5;
        }
        // приземление на окно
        if (vy > 0) {
          for (final wi in fallCands) {
            if (prevY <= wi.t + 1 && y >= wi.t && x > wi.l + 30 * u && x < wi.r - 30 * u && !wi.zoomed) {
              if (wi.t - (footLine - headTop) * s < 0) continue;
              final alive = w.windowAlive(wi.h);
              if (alive != null && (alive.t - wi.t).abs() < 2) {
                if (w.rootAt(x, wi.t + _probeOffset) == wi.h) {
                  _land(wi.t, wi.h, wi.l);
                  return;
                }
              }
            }
          }
        }
        if (y >= ga.b) _land(ga.b, 0, 0);
      case Loc.jump:
        if (now < jPrep) return;
        final p = (now - jT0) / jDur;
        if (p >= 1) {
          x = jx1;
          y = jy1;
          vy = ((jy1 - jy0) + 4 * jH) / jDur; // скорость в конце дуги — для силы приземления
          fallStartY = y; // это прыжок, а не падение: не пугаемся
          if (jSurf != 0) {
            final wi = w.windowAlive(jSurf);
            if (wi != null && (wi.t - jSurfT).abs() < 3 && !wi.zoomed) {
              _land(wi.t, jSurf, wi.l);
              x = wi.l + (jx1 - jSurfL);
              surfRel = x - wi.l;
              if (rnd.nextDouble() < 0.35 && canChat) say(pick('windowHop'), 0);
              return;
            }
            vy = 0;
            startFall();
            return;
          }
          _land(_groundAt(x, y).b, 0, 0);
          return;
        }
        x = jx0 + (jx1 - jx0) * p;
        y = jy0 + (jy1 - jy0) * p - jH * 4 * p * (1 - p);
        facing = jx1 > jx0 ? 1 : -1;
      case Loc.ground:
        final ga = _groundAt(x, y);
        if (ga.b > y + 3) {
          startFall();
          return;
        }
        y = ga.b;
        _walkStep(dt, ga.l + halfW, ga.r - halfW);
      case Loc.window:
        if (now >= surfCheckAt) {
          surfCheckAt = now + 0.12;
          final wi = w.windowAlive(surf);
          if (wi == null || wi.zoomed) {
            startFall();
            return;
          }
          x = wi.l + surfRel;
          y = wi.t;
          if (x < wi.l + 20 * u || x > wi.r - 20 * u) {
            startFall();
            return;
          }
          if (wi.t - (footLine - headTop) * s * 0.7 < 0) {
            startFall();
            return;
          }
          final root = w.rootAt(x, wi.t + _probeOffset);
          if (root != surf && root != 0 && !w.ownWindow(root)) {
            surfMissCount++;
            if (surfMissCount > 2) {
              startFall();
              return;
            }
          } else {
            surfMissCount = 0;
          }
          _walkStep(dt, wi.l + halfW * 0.7, wi.r - halfW * 0.7);
          surfRel = x - wi.l;
        } else {
          final wi = w.windowAlive(surf);
          if (wi != null) {
            _walkStep(dt, wi.l + halfW * 0.7, wi.r - halfW * 0.7);
            surfRel = x - wi.l;
          }
        }
    }
  }

  double get _probeOffset => (10 * s).ceilToDouble() + 6;

  void _land(double ly, int onSurf, double surfL) {
    final impact = vy;
    y = ly;
    vx = vy = 0;
    if (onSurf != 0) {
      loc = Loc.window;
      surf = onSurf;
      surfRel = x - surfL;
      surfMissCount = 0;
    } else {
      loc = Loc.ground;
      surf = 0;
    }
    anim.land(math.min(0.2, 0.06 + math.max(0, impact) / (9000 * u)));
    nextDecide = now + randf(3, 7);
    if (!entranceDone) {
      entranceDone = true;
      _greet();
      return;
    }
    if (longDrag) {
      longDrag = false;
      setEmote('offended', 2.8);
      say(pick('offended'), 1);
      return;
    }
    if (fallStartY < ly - 250 * u && impact > 1100 * u) {
      setEmote('scared', 0.9);
      if (rnd.nextDouble() < 0.6) say(pick('dropped'), 1);
    }
  }

  /// Ходьба: поворот боком → плавный разгон → шаги → плавное торможение.
  void _walkStep(double dt, double minX, double maxX) {
    if (!walking) return;
    if (walkPhase == WalkPhase.turn) {
      if (now - walkT0 < _turnDur) return;
      walkPhase = WalkPhase.move;
    }
    if (walkPhase == WalkPhase.move && (now >= walkEnd || maxX <= minX)) walkPhase = WalkPhase.stop;
    final target = walkPhase == WalkPhase.move ? walkSpeed : 0.0;
    final acc = walkSpeed / _rampDur * dt;
    walkVel = walkVel < target ? math.min(target, walkVel + acc) : math.max(target, walkVel - acc);
    if (walkPhase == WalkPhase.stop && walkVel <= 0) {
      stopWalk();
      nextDecide = now + randf(4, 11);
      return;
    }
    final step = walkVel * dt;
    x += facing * step;
    walkDist += step;
    if (x < minX) {
      x = minX;
      facing = 1;
    }
    if (x > maxX) {
      x = maxX;
      facing = -1;
    }
  }

  /// Можно ли сейчас болтать по своей инициативе.
  bool get canChat =>
      !cfg.dnd && !hidden && !fsHidden && pomo != Pomo.focus && bug == BugState.none && !sleeping && quitAt == 0;

  void _idleMind() {
    if (busy || walking || sleeping || bug != BugState.none || quitAt > 0) return;
    if (emoting) return;
    if (pomo == Pomo.focus) return;
    if (now < nextDecide) return;
    nextDecide = now + randf(5, 13);
    final r = rnd.nextDouble();
    if (cfg.walk && r < 0.5) {
      walking = true;
      walkPhase = WalkPhase.turn;
      walkT0 = now;
      walkVel = 0;
      walkEnd = now + _turnDur + randf(2.5, 8);
      walkSpeed = randf(38, 58) * u * (s / (0.4 * u));
      if (rnd.nextInt(2) == 0) facing = -facing;
    } else if (cfg.windowHop && r < 0.68 && loc == Loc.ground) {
      tryHopToWindow();
    } else if (loc == Loc.window && r < 0.8) {
      _jumpDown();
    }
  }

  bool tryHopToWindow() {
    final ga = _groundAt(x, y);
    final best = <WinInfo>[];
    for (final wi in w.candidateWindows()) {
      if (wi.zoomed || wi.r - wi.l < 260 * u) continue;
      if (wi.t - (footLine - headTop) * s * 1.05 < ga.t || wi.t > ga.b - 140 * u) continue;
      final cx = math.max(wi.l + 90 * u, math.min(x, wi.r - 90 * u));
      if ((cx - x).abs() > 1100 * u) continue;
      best.add(wi);
    }
    if (best.isEmpty) return false;
    final wi = best[rnd.nextInt(best.length)];
    final lx = math.max(wi.l + 90 * u, math.min(x + randf(-140, 140) * u, wi.r - 90 * u));
    if (w.rootAt(lx, wi.t + _probeOffset) != wi.h) return false;
    _startJump(lx, wi.t, wi.h, wi.l);
    return true;
  }

  void _jumpDown() {
    final dir = rnd.nextInt(2) == 0 ? -1.0 : 1.0;
    var tx = x + dir * randf(60, 140) * u;
    final wa = w.workArea(tx, y);
    tx = math.max(wa.l + halfW, math.min(tx, wa.r - halfW));
    _startJump(tx, wa.b, 0, 0);
  }

  void _startJump(double tx, double ty, int toSurf, double surfL) {
    stopWalk();
    loc = Loc.jump;
    surf = 0;
    jx0 = x;
    jy0 = y;
    jx1 = tx;
    jy1 = ty;
    jSurf = toSurf;
    jSurfL = surfL;
    jSurfT = ty;
    final d = math.sqrt((tx - x) * (tx - x) + (ty - y) * (ty - y));
    jDur = 0.5 + d / (2600 * u);
    jH = ty < y ? (y - ty) * 0.55 + 90 * u : 50 * u;
    jPrep = now + 0.12; // присед перед прыжком
    jT0 = jPrep;
  }

  void _greet() {
    if (!cfg.firstRunDone) {
      cfg.firstRunDone = true;
      setEmote('pathos', 2.5);
      final list = phrases['firstRun']!;
      say(list[0], 3);
      for (final p in list.skip(1)) {
        queueSay(p, 3);
      }
      tipAt = now + 30;
      return;
    }
    final h = DateTime.now().hour;
    var key = 'greetDay';
    if (h >= 5 && h < 12) {
      key = 'greetMorning';
    } else if (h >= 18 && h < 23) {
      key = 'greetEvening';
    } else if (h >= 23 || h < 5) {
      key = 'greetNight';
    }
    setEmote('wave', 2);
    say(pick(key), 2);
    tipAt = now + 12;
  }

  void _updateBubbleQueue() {
    if (bText.isNotEmpty && now >= bUntil) {
      bText = '';
      bGapUntil = now + 0.35;
    }
    if (bText.isEmpty && bQueue.isNotEmpty && now >= bGapUntil) _showBubble(bQueue.removeAt(0));
  }

  // ---------- Раз в секунду ----------

  void _second() {
    final fs = w.fullscreen();
    if (fs != fsHidden) {
      fsHidden = fs;
      if (fs) {
        bUntil = now;
        bug = BugState.none;
      }
    }
    final idle = w.idleSeconds();
    final active = idle < 120;

    // сон: сначала зевает, потом засыпает
    final night = isNight();
    if (!sleeping && !busy && bug == BugState.none && quitAt == 0 && (idle > 300 || (night && idle > 150))) {
      sleeping = true;
      stopWalk();
      setEmote('yawn', 1.8);
    }
    if (sleeping && idle < 2) {
      sleeping = false;
      setEmote('excited', 1.4);
      if (rnd.nextDouble() < 0.6) say(pick('wake'), 1);
      nextDecide = now + 3;
    }

    // помодоро
    if (pomo != Pomo.off && now >= pomoEnd) {
      if (pomo == Pomo.focus) {
        cfg.pomosDone++;
        pomoCycle++;
        final brk = pomoCycle % 4 == 0 ? cfg.pomoLong : cfg.pomoBreak;
        pomo = Pomo.rest;
        pomoEnd = now + brk * 60;
        setEmote('excited', 3);
        say(pick('pomoEnd'), 3);
        if (hidden || fsHidden) w.notify('Dartty', 'Помодоро завершён! Перерыв $brk мин.');
      } else {
        pomo = Pomo.off;
        pomoOffer = now + 180;
        setEmote('pathos', 2);
        say('${pick('breakEnd')} Кликни меня — начнём новый помодоро.', 3);
        if (hidden || fsHidden) w.notify('Dartty', 'Перерыв окончен! Возвращаемся к коду?');
      }
    }

    // программы и опыт
    final (proc, title) = w.foreground();
    final cat = categorize(proc);
    if (cat == 'ide' || cat == 'terminal' || cat == 'emulator') {
      if (idle < 90) {
        cfg.codingSeconds++;
        codingMinAcc++;
        codingHourAcc++;
        if (codingMinAcc >= 60) {
          codingMinAcc = 0;
          _addXP(1);
        }
      }
    }
    _reactToApps(cat, proc, title, active);

    if (!active) {
      if (idle > 300) sitAcc = 0;
    } else {
      waterAcc++;
      sitAcc++;
      if (!hidden && !fsHidden) bugAcc++;
    }
    _reminders(active, night);

    // болтовня
    if (cfg.chatter && canChat && active && now >= nextChatter) {
      nextChatter = now + randf(7 * 60, 14 * 60);
      if (loc == Loc.ground || loc == Loc.window) say(pick('idleChatter'), 0);
    }

    // совет дня
    if (tipAt > 0 && now >= tipAt && canChat) {
      tipAt = 0;
      final d = DateTime.now();
      final today = '${d.year}-${_two(d.month)}-${_two(d.day)}';
      if (cfg.lastTipDate != today) {
        cfg.lastTipDate = today;
        final tip = _nextTip();
        setEmote('pathos', 1.4);
        sayFull(tip, 'Совет дня', 2, math.max(9, math.min(16, 3 + 0.07 * tip.runes.length)));
      }
    }

    // Баг
    if (cfg.bugs && canChat && active && idle < 60 && bugAcc >= bugNeed && !busy) {
      bugAcc = 0;
      bugNeed = randf(30 * 60, 70 * 60);
      _spawnBug();
    }

    _idleMind();

    if (now >= saveAt) {
      saveAt = now + 300;
      persist();
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  void persist() {
    cfg
      ..posX = x
      ..posY = y
      ..hasPos = true;
    _save(cfg);
  }

  static bool isNight() {
    final h = DateTime.now().hour;
    return h >= 23 || h < 5;
  }

  static String categorize(String proc) {
    var p = proc.toLowerCase();
    final i = math.max(p.lastIndexOf(r'\'), p.lastIndexOf('/'));
    if (i >= 0) p = p.substring(i + 1);
    if (p.endsWith('.exe')) p = p.substring(0, p.length - 4);
    if (p.isEmpty) return '';
    for (final cat in const ['ide', 'terminal', 'emulator', 'browser', 'messenger', 'claude']) {
      if (appCategories[cat]!.contains(p)) return cat;
    }
    return 'other';
  }

  bool _cooldown(String key, double sec) {
    if (now < (cool[key] ?? 0)) return false;
    cool[key] = now + sec;
    return true;
  }

  void _reactToApps(String cat, String proc, String title, bool active) {
    if (cat != curCat) {
      final prev = curCat;
      curCat = cat;
      catSince = now;
      if (prev == 'ide') lastIdeSeen = now;
      if (cfg.appReact && canChat && entranceDone) {
        switch (cat) {
          case 'ide':
            if ((now - lastIdeSeen > 240 || lastIdeSeen == 0) && _cooldown('ide', 600)) {
              setEmote('excited', 2);
              say(pick('codingStart'), 1);
            }
          case 'terminal':
            if (rnd.nextDouble() < 0.25 && _cooldown('term', 1800)) say(pick('terminal'), 1);
          case 'emulator':
            if (_cooldown('emu', 1800)) {
              setEmote('excited', 1.5);
              say(pick('emulator'), 1);
            }
          case 'claude':
            if (_cooldown('claude', 7200)) {
              setEmote('excited', 1.5);
              say(pick('claude'), 1);
            }
        }
      }
    }
    if (cat == 'ide') {
      lastIdeSeen = now;
      if (now - catSince > 60) {
        browseAcc = 0;
        ytAcc = 0;
      }
    }
    final lt = title.toLowerCase();
    final isDev = devSites.any(lt.contains);
    if (cat == 'browser' && active) {
      if (lt.contains('claude') && cfg.appReact && canChat && _cooldown('claude', 7200)) say(pick('claude'), 1);
      if (lt.contains('youtube')) {
        ytAcc++;
      } else if (!isDev) {
        browseAcc++;
      }
      if (title != lastTitle && isDev && cfg.appReact && canChat && rnd.nextDouble() < 0.5 && _cooldown('dev', 2400)) {
        setEmote('curious', 1.5);
        say(pick('devBrowse'), 1);
      }
    }
    if (cat == 'messenger' && active) {
      msgAcc++;
    } else if (cat != 'messenger') {
      msgAcc = math.max(0, msgAcc - 0.5);
    }
    lastTitle = title;
    if (!cfg.appReact || !canChat) return;
    if (ytAcc >= 5 * 60 && cat == 'browser' && _cooldown('yt', 1800)) {
      ytAcc = 0;
      setEmote('curious', 2);
      say(pick('youtube'), 1);
    }
    if (browseAcc >= 20 * 60 && cat == 'browser' && _cooldown('browse', 1500)) {
      browseAcc = 0;
      setEmote('offended', 2.2);
      say(pick('browserTease'), 1);
    }
    if (msgAcc >= 15 * 60 && cat == 'messenger' && _cooldown('msg', 1800)) {
      msgAcc = 0;
      say(pick('messenger'), 1);
    }
    if (codingHourAcc >= 3600) {
      codingHourAcc = 0;
      setEmote('proud', 2);
      say(pick('codingHour'), 2);
    }
  }

  void _reminders(bool active, bool night) {
    final can =
        !cfg.dnd && !hidden && !fsHidden && pomo != Pomo.focus && bug == BugState.none && quitAt == 0 && !sleeping;
    if (!can || !active) return;
    if (cfg.water && waterAcc >= cfg.waterMin * 60) {
      waterAcc = 0;
      setEmote('excited', 1.6);
      say(pick('water'), 2);
      return;
    }
    if (cfg.stretch && sitAcc >= 3600) {
      sitAcc = 0;
      setEmote('pathos', 2);
      say(pick('stretch'), 2);
      return;
    }
    if (cfg.night && night && now >= nextNight) {
      nextNight = now + 40 * 60;
      setEmote('yawn', 2.6);
      say(pick('nightSleep'), 2);
    }
  }

  // ---------- Баг ----------

  double get _bugScale => s * 0.85;

  void _spawnBug() {
    stopWalk();
    sleeping = false;
    bug = BugState.fight;
    bugMaxHP = 7;
    bugHP = bugMaxHP;
    bugStart = now;
    bugEnd = now + 10.5;
    final wa = w.workArea(x, y - 10 * u);
    var side = 1.0;
    if (x + 400 * u > wa.r) {
      side = -1;
    } else if (x - 400 * u > wa.l && rnd.nextInt(2) == 0) {
      side = -1;
    }
    bugX = x + side * randf(280, 380) * u;
    bugY = y - randf(0, 80) * u;
    _clampBug(wa.l, wa.t, wa.r);
    bugFX = bugTX = bugX;
    bugFY = bugTY = bugY;
    bugMoveT0 = now;
    bugMoveDur = 0.01;
    bugNextMove = now + 0.9;
    bugFacing = -side;
    facing = side;
    setEmote('scared', 0.8);
    sayFull(pick('bugAppear'), '', 2, 2.8);
  }

  void _clampBug(double l, double t, double r) {
    final bw = 150 * _bugScale, bh = 300 * _bugScale;
    bugX = math.max(l + bw, math.min(bugX, r - bw));
    final gb = w.workArea(bugX, bugY).b;
    bugY = math.max(t + bh + 30 * u, math.min(bugY, gb));
  }

  void _updateBug(double dt) {
    if (bug == BugState.none) return;
    switch (bug) {
      case BugState.none:
        return;
      case BugState.fight:
        if (now >= bugEnd) {
          bug = BugState.lose;
          bugPhaseAt = now;
          final wa = w.workArea(bugX, bugY);
          bugFX = bugX;
          bugFY = bugY;
          bugTX = bugX - wa.l < wa.r - bugX ? wa.l - 300 * u : wa.r + 300 * u;
          bugTY = bugY - 200 * u;
          bugMoveT0 = now;
          bugMoveDur = 0.8;
          cfg.bugsEscaped++;
          setEmote('sad', 3);
          sayFull(pick('bugLose'), '', 3, 3.5);
          return;
        }
        if (!emoting) setEmote('angry', 0.6);
        if (now >= bugNextMove) {
          final wa = w.workArea(x, y - 10 * u);
          bugFX = bugX;
          bugFY = bugY;
          var nx = x + randf(-520, 520) * u;
          if ((nx - x).abs() < 250 * u) nx = nx < x ? x - randf(250, 330) * u : x + randf(250, 330) * u;
          bugTX = nx;
          bugTY = y - randf(0, 110) * u;
          final ox = bugX, oy = bugY;
          bugX = bugTX;
          bugY = bugTY;
          _clampBug(wa.l, wa.t, wa.r);
          bugTX = bugX;
          bugTY = bugY;
          bugX = ox;
          bugY = oy;
          bugMoveT0 = now;
          bugMoveDur = randf(0.28, 0.45);
          bugNextMove = now + bugMoveDur + randf(0.45, 1.0);
          bugFacing = bugTX > bugFX ? 1 : -1;
        }
        final p = math.min(1.0, (now - bugMoveT0) / bugMoveDur);
        final e = p * p * (3 - 2 * p);
        bugDashing = p < 1;
        bugX = bugFX + (bugTX - bugFX) * e;
        bugY = bugFY + (bugTY - bugFY) * e - math.sin(p * math.pi) * 25 * u;
        if (!bugDashing) {
          bugY = bugTY + math.sin(now * 3) * 4 * u;
          bugFacing = x > bugX ? 1 : -1;
        }
        facing = x > bugX ? -1 : 1;
      case BugState.win:
        final gb = w.workArea(bugX, bugY).b;
        bugVY += 2600 * u * dt;
        bugY = math.min(gb, bugY + bugVY * dt);
        bugDashing = false;
        if (now >= bugEnd) bug = BugState.none;
      case BugState.lose:
        final p = math.min(1.0, (now - bugMoveT0) / bugMoveDur);
        final e = p * p;
        bugDashing = true;
        bugX = bugFX + (bugTX - bugFX) * e;
        bugY = bugFY + (bugTY - bugFY) * e;
        if (p >= 1) bug = BugState.none;
    }
  }

  // ---------- Поза ----------

  /// Выбирает позу и цели для пружин (как currentPose в Go-версии).
  void _updatePose(double dt) {
    final it = _intent..reset();
    final t = now;
    final hh = footLine * s;
    String p;
    if (loc == Loc.drag) {
      p = now - dragStart > 2.5 ? 'offended' : 'scared';
      it.shakeX = math.sin(t * 7) * 2 * u;
      it.sway = 4 + math.min(4, (dvx.abs() + dvy.abs()) / (300 * u));
      it.swaySpeed = 7;
    } else if (loc == Loc.air) {
      p = 'scared';
      if (vy > 300 * u) {
        it.sx = 0.96;
        it.sy = 1.05;
      }
      it.sway = 6;
      it.swaySpeed = 9;
    } else if (loc == Loc.jump) {
      p = 'excited';
      if (now < jPrep) {
        it.sx = 1.08;
        it.sy = 0.86; // присед
      } else {
        it.sx = 0.94;
        it.sy = 1.07; // растяжение в полёте
      }
      it.sway = 5;
      it.swaySpeed = 8;
    } else if (emoting) {
      p = emote;
    } else if (sleeping) {
      p = 'sleep';
    } else if (walking) {
      p = walkPhase == WalkPhase.turn ? 'side' : 'walk';
    } else if (loc == Loc.window) {
      p = 'edge';
    } else if (pomo == Pomo.focus) {
      p = 'focused';
    } else {
      p = 'idle';
    }
    if (emote.isNotEmpty && now >= emoteEnd) emote = '';

    // любопытство: смотрит на курсор
    if (p == 'idle' && now > curiousBlockTil && !pressed) {
      final (cx, cy) = w.cursor();
      final hx = x, hy = y - hh * 0.5;
      final d = math.sqrt((cx - hx) * (cx - hx) + (cy - hy) * (cy - hy));
      if (d < 260 * s + 60 * u) {
        if (curiousSince == 0) curiousSince = now;
        if (now - curiousSince > 0.4 && now - curiousSince < 7) {
          p = 'curious';
          facing = cx < x ? -1 : 1;
        } else if (now - curiousSince >= 7) {
          curiousBlockTil = now + 25;
          curiousSince = 0;
        }
      } else {
        curiousSince = 0;
      }
    }

    final et = now - emoteStart;
    switch (p) {
      case 'sleep':
        final k = math.sin(t * 1.4);
        it.sy = 1 + 0.022 * k;
        it.sx = 1 - 0.01 * k;
        it.breathe = false;
        it.sway = 0.5;
        it.swaySpeed = 1.2;
      case 'focused':
        it.sy = 1 + 0.004 * math.sin(t * 2);
      case 'excited':
        if (loc == Loc.ground || loc == Loc.window) {
          final ph = math.sin(et * 7.5).abs();
          it.offY = ph * 0.11 * hh;
          if (ph < 0.25) {
            it.sx = 1.05;
            it.sy = 0.95;
          }
        }
      case 'pathos':
        final k = 1 + 0.03 * math.sin(et * 8);
        it.sx = k;
        it.sy = k;
        it.sway = 2.5;
        it.swaySpeed = 4;
      case 'angry':
        it.shakeX = math.sin(t * 45) * 1.6 * u;
        it.sy = 1 + 0.02 * math.sin(t * 9);
      case 'scared':
        if (loc != Loc.air) it.shakeX = math.sin(t * 55) * 2.2 * u;
      case 'curious':
        // лёгкий наклон к курсору (±3°)
        final (cx, _) = w.cursor();
        it.tilt = (3 * math.pi / 180) * ((cx - x) / (200 * u)).clamp(-1.0, 1.0);
      case 'sad':
        it.sy = 1 - 0.012 * (1 + math.sin(t * 1.2)) / 2;
      case 'proud':
        it.sy = 1.02 + 0.01 * math.sin(et * 3);
        it.sx = 1.01;
      case 'wave':
        it.tilt = 0.035 * math.sin(et * 6);
      case 'yawn':
        it.sy = 1 + 0.04 * math.sin(math.min(1.0, et / 1.6) * math.pi);
        it.sx = 1 - 0.015 * math.sin(math.min(1.0, et / 1.6) * math.pi);
      case 'edge':
        it.sway = 1.6; // лапки свисают и слегка покачиваются
        it.swaySpeed = 2.6;
      case 'walk':
        final amt = walkSpeed > 0 ? (walkVel / walkSpeed).clamp(0.0, 1.0) : 0.0;
        it.walkAmt = amt;
        it.sway = 1.5 + 4 * amt;
        it.swaySpeed = 2.2 + 7 * amt;
    }
    it.walkDist = walkDist;
    // направление
    switch (p) {
      case 'walk' || 'side' || 'curious' || 'offended':
        it.flip = facing < 0;
      case 'excited':
        it.flip = loc == Loc.jump && facing < 0;
    }
    it.pose = p;
    pose = p;
    anim.update(now, dt, it);
  }

  // ---------- Рисование ----------

  void _renderMascot(bool draw) {
    final vis = !hidden && !fsHidden;
    mascot.visible = vis;
    if (!vis) return;
    final tx = x + anim.dx - wc / 2, ty = y + anim.dy - footY;
    var ix = tx.floor(), iy = ty.floor();
    var fx = q(tx - ix, 1 / 8), fy = q(ty - iy, 1 / 8);
    if (fx >= 1) {
      ix++;
      fx = 0;
    }
    if (fy >= 1) {
      iy++;
      fy = 0;
    }
    mascot.x = ix;
    mascot.y = iy;
    if (!draw) return;
    final f = anim.frame(s, fx, fy);
    final key = '${f.key}|${cfg.size}';
    if (key == renderKey) return;
    renderKey = key;
    var img = mascot.img;
    if (img == null || img.w != wc || img.h != hc) img = mascot.img = Img(wc, hc);
    _statWatch
      ..reset()
      ..start();
    renderer.render(img, f, s, wc / 2 + fx, footY + fy);
    statRenders++;
    statRenderUs += _statWatch.elapsedMicroseconds;
    mascot.dirty = true;
  }

  void _renderBubble(bool draw) {
    final vis = bText.isNotEmpty && now < bUntil && !hidden && !fsHidden;
    bubble.visible = vis;
    if (!vis || !draw) return;
    final pad = 14 * u, border = 2 * u, tailH = 12 * u, tailW = 18 * u;
    if (bubbleImg == null) {
      final maxW = (bText.runes.length > 90 ? 340 * u : 280 * u).toInt();
      _bBody = w.renderText(bText, bold: false, px: (15 * u).round(), maxW: maxW);
      _bHead = TextBlock.empty;
      var gap = 0;
      if (bHeader.isNotEmpty) {
        _bHead = w.renderText(bHeader, bold: true, px: (13 * u).round(), maxW: maxW);
        gap = (5 * u).toInt();
      }
      final tw = math.max(_bBody.w, _bHead.w);
      _bW = tw + 2 * pad;
      _bH = _bBody.h + _bHead.h + gap + 2 * pad - 4 * u;
      _bMar = 6 * u;
      _bPad = pad;
      _bGap = gap.toDouble();
      final img = bubbleImg = Img((_bW + 2 * _bMar).ceil(), (_bH + tailH + 2 * _bMar).ceil());
      // Основа без хвостика: рамка, заливка и текст. Хвостик дорисовывается отдельно.
      final base = _bubbleBase = Img(img.w, img.h);
      drawBubble(base, _bMar, _bMar, _bW, _bH, 12 * u, -1e4, tailW, tailH, border);
      var ty = (_bMar + _bPad - 2 * u).toInt();
      final tx = (_bMar + _bPad).toInt();
      if (_bHead.h > 0) {
        blendCoverage(base, _bHead.cov, _bHead.w, _bHead.h, tx, ty, colAccent);
        ty += _bHead.h + _bGap.toInt();
      }
      blendCoverage(base, _bBody.cov, _bBody.w, _bBody.h, tx, ty, colText);
      bubbleKey = '';
    }
    // позиция: над головой
    final mar = _bMar, bw = _bW, bh = _bH;
    var headY = y - (contactLine(pose) - headTop) * s - 4 * u;
    if (loc == Loc.drag || loc == Loc.air || loc == Loc.jump) headY -= 6 * u;
    final wa = w.workArea(x, y - 10 * u);
    var bx = x - bw / 2 - mar;
    bx = math.max(wa.l + 4 * u - mar, math.min(bx, wa.r - 4 * u - bw - mar));
    var by = headY - (bh + tailH + mar);
    if (by < wa.t) by = wa.t;
    var tailX = math.max(mar + 16 * u + tailW / 2, math.min(x - bx, mar + bw - 16 * u - tailW / 2));
    tailX = q(tailX, 2);
    final key = tailX.toStringAsFixed(0);
    if (key != bubbleKey) {
      bubbleKey = key;
      final img = bubbleImg!;
      img.pix.setAll(0, _bubbleBase!.pix);
      final reach = tailW / 2 + (border + 3) * 0.8 + 3;
      drawBubble(img, mar, mar, bw, bh, 12 * u, tailX, tailW, tailH, border,
          x0: (tailX - reach).floor(), y0: (mar + bh - 3).floor(), x1: (tailX + reach).ceil());
      bubble.img = img;
      bubble.dirty = true;
    }
    bubble.x = bx.round();
    bubble.y = by.round();
  }

  void _renderBug(bool draw) {
    final vis = bug != BugState.none && !hidden && !fsHidden;
    bugLayer.visible = vis;
    if (!vis) return;
    final bs = _bugScale;
    final bw = (360 * bs).ceil() + 4;
    final barH = 7 * u;
    final top = (barH * 2 + 10 * u).ceilToDouble();
    final fy = top + (footLine * bs).ceil();
    final bh = (fy + (10 * bs).ceil() + 3).toInt();

    var p = bugDashing && bug == BugState.fight ? 'bug_attack' : 'bug_idle';
    var alpha = 1.0;
    if (bug == BugState.win) {
      p = 'bug_dead';
      final k = (now - bugPhaseAt) / 1.5;
      alpha = math.max(0, 1 - k * k);
    }
    if (bug == BugState.lose) {
      p = 'bug_attack';
      alpha = math.max(0, 1 - (now - bugPhaseAt) / 0.8);
    }
    if (bug == BugState.fight && now - bugStart < 0.45) alpha = (now - bugStart) / 0.45;
    var flip = bugFacing < 0;
    if (p == 'bug_idle' || p == 'bug_dead') flip = false;
    final flash = now < bugFlash ? 0.75 : 0.0;
    final hpFrac = bugHP / bugMaxHP;
    final timeFrac = math.max(0.0, (bugEnd - now) / 10.5);
    final showBars = bug == BugState.fight;
    bugLayer.alpha = (255 * alpha.clamp(0.0, 1.0)).round();
    final shake = now < bugFlash ? math.sin(now * 90) * 4 * u : 0.0;
    bugLayer.x = (bugX - bw / 2 + shake).round();
    bugLayer.y = (bugY - fy).round();
    if (!draw) return;
    final key = '$p|$flip|$flash|${hpFrac.toStringAsFixed(2)}|${q(timeFrac, 0.02).toStringAsFixed(2)}|$showBars|$bs';
    if (key == bugKey) return;
    bugKey = key;
    var img = bugLayer.img;
    if (img == null || img.w != bw || img.h != bh) {
      img = bugLayer.img = Img(bw, bh);
    } else {
      img.clear();
    }
    final sp = bank.get(p, bs);
    final k = sp.h / canvasH;
    final m =
        Affine.translate(bw / 2, fy) * Affine.scale(flip ? -1 : 1, 1) * Affine.translate(-sp.w / 2, -footLine * k);
    drawImage(img, sp, m, flash: flash);
    if (showBars) {
      final barW = 120 * u;
      final bx = (bw - barW) / 2;
      drawBar(img, bx, 2 * u, barW, barH, hpFrac, colBugBar);
      drawBar(img, bx + barW * 0.15, 4 * u + barH, barW * 0.7, barH * 0.6, timeFrac, colTimeBar);
    }
    bugLayer.dirty = true;
  }
}
