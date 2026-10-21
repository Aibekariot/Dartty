// Windows-оболочка Dartty: три слоистых окна (Dartty, облачко, Баг), скрытое окно
// для трея и меню, синхронный цикл сообщений на 60 кадров в секунду.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../app.dart';
import '../assets_data.dart';
import '../gfx.dart';
import '../log.dart';
import '../settings.dart';
import '../sprites.dart';
import '../world.dart';
import 'ffi.dart';
import 'win32.dart';
import 'win_world.dart';
import 'worker.dart';

// ---------- Слоистое окно с попиксельной прозрачностью ----------

class LayeredWindow {
  int hwnd = 0;
  int _memDC = 0, _bmp = 0, _oldBmp = 0;
  Pointer<Uint8> _bits = nullptr;
  int _w = 0, _h = 0, x = 0, y = 0, alpha = 255;
  bool shown = false, _clickThrough = false, _presented = false;

  static final _ptDst = mem<POINT>(), _ptSrc = mem<POINT>();
  static final _size = mem<SIZE>();
  static final _blend = mem<BLENDFUNCTION>();
  static final _bmi = mem<BITMAPINFOHEADER>(2);
  static final _bitsOut = mem<Pointer<Uint8>>();

  void _ensure(int w, int h) {
    if (_memDC == 0) _memDC = CreateCompatibleDC(0);
    if (_bmp != 0 && _w == w && _h == h) return;
    if (_bmp != 0) {
      SelectObject(_memDC, _oldBmp);
      DeleteObject(_bmp);
      _bmp = 0;
    }
    _bmi.ref
      ..biSize = sizeOf<BITMAPINFOHEADER>()
      ..biWidth = w
      ..biHeight = -h
      ..biPlanes = 1
      ..biBitCount = 32;
    _bmp = CreateDIBSection(_memDC, _bmi, 0, _bitsOut, 0, 0);
    _oldBmp = SelectObject(_memDC, _bmp);
    _bits = _bitsOut.value;
    _w = w;
    _h = h;
  }

  static int presents = 0, presentUs = 0;
  static final _presentWatch = Stopwatch();

  void _present(Img img, int px, int py, int a) {
    _presentWatch
      ..reset()
      ..start();
    _ensure(img.w, img.h);
    if (_bits.address == 0) return;
    _bits.asTypedList(img.w * img.h * 4).setAll(0, img.pix);
    GdiFlush();
    final screen = GetDC(0);
    _ptDst.ref
      ..x = px
      ..y = py;
    _size.ref
      ..cx = img.w
      ..cy = img.h;
    _blend.ref
      ..BlendOp = 0
      ..BlendFlags = 0
      ..SourceConstantAlpha = a
      ..AlphaFormat = AC_SRC_ALPHA;
    UpdateLayeredWindow(hwnd, screen, _ptDst, _size, _memDC, _ptSrc, 0, _blend, ULW_ALPHA);
    ReleaseDC(0, screen);
    x = px;
    y = py;
    alpha = a;
    _presented = true;
    presents++;
    presentUs += _presentWatch.elapsedMicroseconds;
  }

  void apply(Layer ly) {
    final img = ly.img;
    if (!ly.visible || img == null) {
      if (shown) {
        ShowWindow(hwnd, SW_HIDE);
        shown = false;
      }
      return;
    }
    if (ly.dirty || !_presented || ly.alpha != alpha) {
      _present(img, ly.x, ly.y, ly.alpha);
      ly.dirty = false;
    } else if (ly.x != x || ly.y != y) {
      SetWindowPos(hwnd, 0, ly.x, ly.y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
      x = ly.x;
      y = ly.y;
    }
    if (!shown) {
      ShowWindow(hwnd, SW_SHOWNOACTIVATE);
      setTopmost();
      shown = true;
    }
  }

  void setTopmost() => SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

  void setClickThrough(bool on) {
    if (_clickThrough == on) return;
    _clickThrough = on;
    var ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    ex = on ? ex | WS_EX_TRANSPARENT : ex & ~WS_EX_TRANSPARENT;
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex);
  }
}

// ---------- Состояние ----------

const _wmTray = WM_APP + 1;
const _wmUnhide = WM_APP + 2;
const _wmWorker = WM_APP + 3;
const _ctlClass = 'DarttyCtl';
const _layerClass = 'DarttyLayer';

late App _app;
late WinWorld _world;
Worker? _worker;
int _hInst = 0, _ctl = 0, _trayIcon = 0, _bigIcon = 0, _cursorHand = 0, _cursorMove = 0;
int _msgTaskbarCreated = 0;
bool _quitting = false, _trayAdded = false;
final _mascotWin = LayeredWindow(), _bubbleWin = LayeredWindow(), _bugWin = LayeredWindow();
final _clock = Stopwatch()..start();
double _lastFrame = -1, _lastTopmost = 0, _lastThreadCheck = 0;
int _threadId = 0;
bool _threadWarned = false;

double get _t => _clock.elapsedMicroseconds / 1e6;

bool _isOwn(int h) => h != 0 && (h == _mascotWin.hwnd || h == _bubbleWin.hwnd || h == _bugWin.hwnd || h == _ctl);

// ---------- Трей ----------

Pointer<NOTIFYICONDATAW> _trayData() {
  final nid = mem<NOTIFYICONDATAW>();
  nid.ref
    ..cbSize = sizeOf<NOTIFYICONDATAW>()
    ..hWnd = _ctl
    ..uID = 1;
  return nid;
}

void _addTray() {
  final nid = _trayData();
  nid.ref
    ..uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
    ..uCallbackMessage = _wmTray
    ..hIcon = _trayIcon;
  copyWstr(nid.ref.szTip, 128, 'Dartty');
  _trayAdded = Shell_NotifyIconW(NIM_ADD, nid) != 0;
  mem.free(nid);
}

void _updateTrayTip() {
  if (!_trayAdded) return;
  final li = levelInfo(_app.cfg.xp);
  var tip = 'Dartty — ур. ${li.level}, ${li.title}';
  final (st, left) = _app.pomoState();
  String mmss(double s) => '${s ~/ 60}:${(s.toInt() % 60).toString().padLeft(2, '0')}';
  if (st == Pomo.focus) tip += '\nФокус: осталось ${mmss(left)}';
  if (st == Pomo.rest) tip += '\nПерерыв: ${mmss(left)}';
  if (_app.hidden) tip += '\n(спрятан — кликни, чтобы показать)';
  final nid = _trayData();
  nid.ref.uFlags = NIF_TIP;
  copyWstr(nid.ref.szTip, 128, tip);
  Shell_NotifyIconW(NIM_MODIFY, nid);
  mem.free(nid);
}

void _notify(String title, String text) {
  if (!_trayAdded) return;
  final nid = _trayData();
  nid.ref
    ..uFlags = NIF_INFO
    ..dwInfoFlags = NIIF_INFO;
  copyWstr(nid.ref.szInfoTitle, 64, title);
  copyWstr(nid.ref.szInfo, 256, text);
  Shell_NotifyIconW(NIM_MODIFY, nid);
  mem.free(nid);
}

void _removeTray() {
  if (!_trayAdded) return;
  final nid = _trayData();
  Shell_NotifyIconW(NIM_DELETE, nid);
  mem.free(nid);
  _trayAdded = false;
}

// ---------- Меню ----------

const _idStats = 1, _idTip = 2, _idPomo = 3, _idBug = 4, _idTalk = 5, _idHide = 6, _idQuit = 7;
const _idDND = 8, _idGhost = 9, _idAutostart = 10, _idWalk = 11, _idHop = 12, _idApps = 13;
const _idChatter = 14, _idBugs = 15, _idWater = 16, _idStretch = 17, _idNight = 18, _idSize0 = 100;

void _showMenu() {
  final s = _app.cfg;
  using((a) {
    void item(int m, int id, String text, {bool checked = false, bool disabled = false, bool radio = false}) {
      var f = MF_STRING;
      if (checked) f |= MF_CHECKED;
      if (radio) f |= MF_RADIOCHECK;
      if (disabled) f |= MF_GRAYED;
      AppendMenuW(m, f, id, wstr(text, a));
    }

    void sep(int m) => AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    void sub(int m, int child, String text) => AppendMenuW(m, MF_POPUP, child, wstr(text, a));

    final m = CreatePopupMenu();
    try {
      final li = levelInfo(s.xp);
      item(m, _idStats, 'Dartty · ур. ${li.level} — ${li.title}');
      item(m, 0, 'Опыт ${li.into}/${li.need} · побед над Багом: ${s.bugsDefeated}', disabled: true);
      sep(m);
      item(m, _idTip, 'Совет по Flutter');
      final (st, left) = _app.pomoState();
      String mmss(double v) => '${v ~/ 60}:${(v.toInt() % 60).toString().padLeft(2, '0')}';
      switch (st) {
        case Pomo.off:
          item(m, _idPomo, 'Помодоро: старт (${s.pomoFocus} мин)');
        case Pomo.focus:
          item(m, _idPomo, 'Помодоро: стоп (фокус, осталось ${mmss(left)})', checked: true);
        case Pomo.rest:
          item(m, _idPomo, 'Помодоро: стоп (перерыв, ${mmss(left)})', checked: true);
      }
      item(m, _idBug, 'Вызвать Бага на бой', disabled: _app.hidden);
      sep(m);

      final sizeM = CreatePopupMenu();
      for (var i = 0; i < sizeNames.length; i++) {
        item(sizeM, _idSize0 + i, sizeNames[i], checked: i == s.size, radio: true);
      }
      sub(m, sizeM, 'Размер');

      final behM = CreatePopupMenu();
      item(behM, _idWalk, 'Гулять по панели задач', checked: s.walk);
      item(behM, _idHop, 'Прыгать на края окон', checked: s.windowHop);
      item(behM, _idApps, 'Реагировать на программы', checked: s.appReact);
      item(behM, _idChatter, 'Болтать иногда', checked: s.chatter);
      item(behM, _idBugs, 'Нападения Бага', checked: s.bugs);
      sub(m, behM, 'Поведение');

      final remM = CreatePopupMenu();
      item(remM, _idWater, 'Попить воды (каждые ${s.waterMin} мин)', checked: s.water);
      item(remM, _idStretch, 'Размяться (каждый час)', checked: s.stretch);
      item(remM, _idNight, 'Пора спать (после 23:00)', checked: s.night);
      sub(m, remM, 'Напоминания');
      sep(m);

      item(m, _idDND, 'Не беспокоить', checked: s.dnd);
      item(m, _idGhost, 'Клики сквозь Dartty', checked: s.clickThrough);
      item(m, _idAutostart, 'Запускать вместе с Windows', checked: s.autostart);
      sep(m);
      item(m, _idTalk, 'Поговорить с Dartty (скоро)', disabled: true);
      item(m, _idHide, _app.hidden ? 'Показать Dartty' : 'Спрятать Dartty');
      item(m, _idQuit, 'Выход');

      final pt = a<POINT>();
      GetCursorPos(pt);
      SetForegroundWindow(_ctl);
      // Модальный цикл меню: Dart здесь стоит, кадры идут по WM_TIMER.
      final cmd =
          TrackPopupMenu(m, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, pt.ref.x, pt.ref.y, 0, _ctl, nullptr);
      PostMessageW(_ctl, WM_NULL, 0, 0);
      _onCommand(cmd);
    } finally {
      DestroyMenu(m); // подменю уничтожаются вместе с ним
    }
  });
}

void _onCommand(int id) {
  final s = _app.cfg;
  if (id == 0) return;
  if (id >= _idSize0 && id < _idSize0 + sizeFactors.length) {
    _app.setSize(id - _idSize0);
  } else {
    switch (id) {
      case _idStats:
        _app.showStats();
      case _idTip:
        _app.showTip();
      case _idPomo:
        if (_app.pomoState().$1 == Pomo.off) {
          _app.startPomodoro();
        } else {
          _app.stopPomodoro();
        }
      case _idBug:
        _app.summonBug(training: true);
      case _idHide:
        _app.setHidden(!_app.hidden);
      case _idQuit:
        _app.requestQuit();
      case _idDND:
        _app.setDND(!s.dnd);
      case _idGhost:
        _app.setClickThrough(!s.clickThrough);
      case _idAutostart:
        _app.setAutostart(!s.autostart);
      case _idWalk:
        _app.setWalk(!s.walk);
      case _idHop:
        s.windowHop = !s.windowHop;
      case _idApps:
        s.appReact = !s.appReact;
      case _idChatter:
        s.chatter = !s.chatter;
      case _idBugs:
        s.bugs = !s.bugs;
      case _idWater:
        s.water = !s.water;
      case _idStretch:
        s.stretch = !s.stretch;
      case _idNight:
        s.night = !s.night;
    }
  }
  _app.persist();
  _updateTrayTip();
}

// ---------- Кадр и оконная процедура ----------

// `--stats`: раз в 10 с пишет в журнал, на что уходит время.
bool _stats = false;
int _statFrames = 0, _statFrameUs = 0, _statJank = 0;
double _statPrevT = 0, _statMaxGap = 0;
double _statAt = 0;
final _statPoses = <String, int>{};
final _frameWatch = Stopwatch();

String _avgMs(int us, int n) => (us / (n == 0 ? 1 : n) / 1000).toStringAsFixed(2);

void _logStats(double t) {
  final span = t - _statAt;
  final poses = (_statPoses.entries.toList()..sort((a, b) => b.value - a.value)).map((e) => '${e.key} ${e.value}');
  logf('stats ${span.toStringAsFixed(1)} с: кадров $_statFrames (${(_statFrames / span).toStringAsFixed(1)}/с) '
      'по ${_avgMs(_statFrameUs, _statFrames)} мс; отрисовок ${_app.statRenders} по '
      '${_avgMs(_app.statRenderUs, _app.statRenders)} мс; вывод в окна ${LayeredWindow.presents} по '
      '${_avgMs(LayeredWindow.presentUs, LayeredWindow.presents)} мс; занято '
      '${(_statFrameUs / span / 1e4).toStringAsFixed(2)}% ядра; кадров позже 20 мс: $_statJank, '
      'самая длинная пауза ${(_statMaxGap * 1000).toStringAsFixed(1)} мс; позы: ${poses.join(', ')}');
  _statFrames = _statFrameUs = _statJank = 0;
  _statMaxGap = 0;
  _app.statRenders = _app.statRenderUs = 0;
  LayeredWindow.presents = LayeredWindow.presentUs = 0;
  _statPoses.clear();
  _statAt = t;
}

void _onFrame() {
  try {
    final t = _t;
    _lastFrame = t;
    _frameWatch
      ..reset()
      ..start();
    _app.frame();
    _mascotWin.setClickThrough(_app.cfg.clickThrough);
    _bubbleWin.setClickThrough(_app.cfg.clickThrough);
    _bugWin.apply(_app.bugLayer);
    _mascotWin.apply(_app.mascot);
    _bubbleWin.apply(_app.bubble);
    if (_stats) {
      _statFrames++;
      _statFrameUs += _frameWatch.elapsedMicroseconds;
      final gap = t - _statPrevT;
      _statPrevT = t;
      if (gap > 0.020 && gap < 1) _statJank++;
      if (gap > _statMaxGap && gap < 1) _statMaxGap = gap;
      _statPoses[_app.pose] = (_statPoses[_app.pose] ?? 0) + 1;
      if (t - _statAt >= 10) _logStats(t);
    }
    if (t - _lastTopmost >= 3) {
      _lastTopmost = t;
      for (final w in [_bugWin, _mascotWin, _bubbleWin]) {
        if (w.shown) w.setTopmost();
      }
      _updateTrayTip();
    }
    if (t - _lastThreadCheck >= 2) {
      _lastThreadCheck = t;
      final tid = GetCurrentThreadId();
      if (tid != _threadId && !_threadWarned) {
        _threadWarned = true;
        logf('ВНИМАНИЕ: GUI-код выполняется на другом потоке ($tid вместо $_threadId)');
      }
    }
  } catch (e, st) {
    logf('ошибка в кадре: $e\n$st');
  }
}

int _wndProc(int hwnd, int msg, int wp, int lp) {
  try {
    final r = _handle(hwnd, msg, wp, lp);
    if (r != null) return r;
  } catch (e, st) {
    logf('ошибка в wndProc (msg=0x${msg.toRadixString(16)}): $e\n$st');
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

(double, double) _cursor() => _world.cursor();

int? _handle(int hwnd, int msg, int wp, int lp) {
  if (hwnd == _ctl && _ctl != 0) {
    switch (msg) {
      case WM_TIMER:
        // В модальных циклах (меню) наш цикл стоит — кадры идут отсюда.
        if (wp == 1 && _t - _lastFrame > 0.025) _onFrame();
        return 0;
      case _wmTray:
        switch (lp & 0xffff) {
          case WM_LBUTTONUP:
            _app.setHidden(!_app.hidden);
            _updateTrayTip();
          case WM_RBUTTONUP:
            _showMenu();
        }
        return 0;
      case _wmUnhide:
        _app.setHidden(false);
        return 0;
      case _wmWorker:
        logf('фоновый изолят ответил на запрос $wp: ${Worker.takeReply(lp)}');
        return 0;
      case WM_CLOSE:
        _app.requestQuit();
        return 0;
    }
    if (_msgTaskbarCreated != 0 && msg == _msgTaskbarCreated) {
      _addTray();
      return 0;
    }
  } else if (hwnd == _mascotWin.hwnd) {
    switch (msg) {
      case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
      case WM_SETCURSOR:
        SetCursor(_app.dragging ? _cursorMove : _cursorHand);
        return 1;
      case WM_LBUTTONDOWN:
        SetCapture(hwnd);
        final (x, y) = _cursor();
        _app.onPress(x, y);
        return 0;
      case WM_MOUSEMOVE:
        if (_app.pressed) {
          final (x, y) = _cursor();
          _app.onMove(x, y);
          if (_app.dragging) _onFrame(); // окно следует за мышью без задержки кадра
        }
        return 0;
      case WM_LBUTTONUP:
        final (x, y) = _cursor();
        _app.onRelease(x, y);
        ReleaseCapture();
        return 0;
      case WM_CAPTURECHANGED:
        if (_app.pressed) {
          final (x, y) = _cursor();
          _app.onRelease(x, y);
        }
        return 0;
      case WM_RBUTTONUP:
        _showMenu();
        return 0;
    }
  } else if (hwnd == _bubbleWin.hwnd) {
    switch (msg) {
      case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
      case WM_LBUTTONUP:
        _app.dismissBubble();
        return 0;
      case WM_RBUTTONUP:
        _showMenu();
        return 0;
    }
  } else if (hwnd == _bugWin.hwnd) {
    switch (msg) {
      case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
      case WM_SETCURSOR:
        SetCursor(_cursorHand);
        return 1;
      case WM_LBUTTONDOWN:
        _app.onBugClick();
        return 0;
    }
  }
  return null;
}

// ---------- Запуск ----------

/// Иконка из встроенного .ico: каталог переводится в формат ресурса (GRPICONDIR),
/// LookupIconIdFromDirectoryEx выбирает лучший размер, CreateIconFromResourceEx создаёт HICON.
int iconFromIco(Uint8List ico, int cx, int cy) => using((a) {
      final bd = ByteData.sublistView(ico);
      final count = bd.getUint16(4, Endian.little);
      if (count == 0) return 0;
      final dir = a<Uint8>(6 + 14 * count);
      final dv = dir.asTypedList(6 + 14 * count);
      dv.setRange(0, 6, ico);
      for (var i = 0; i < count; i++) {
        final s = 6 + 16 * i, d = 6 + 14 * i;
        dv.setRange(d, d + 12, ico, s); // размеры, цвета, планы, биты, размер данных
        dv[d + 12] = (i + 1) & 0xff; // вместо смещения — номер ресурса
        dv[d + 13] = (i + 1) >> 8;
      }
      var idx = LookupIconIdFromDirectoryEx(dir, 1, cx, cy, LR_DEFAULTCOLOR) - 1;
      if (idx < 0 || idx >= count) idx = 0;
      final size = bd.getUint32(6 + 16 * idx + 8, Endian.little);
      final off = bd.getUint32(6 + 16 * idx + 12, Endian.little);
      if (off + size > ico.length) return 0;
      final data = a<Uint8>(size);
      data.asTypedList(size).setAll(0, Uint8List.sublistView(ico, off, off + size));
      return CreateIconFromResourceEx(data, size, 1, 0x00030000, cx, cy, LR_DEFAULTCOLOR);
    });

Uint8List _asset(String name) => base64Decode(assetData[name]!);

SpriteBank loadSprites() => SpriteBank.fromPng({for (final n in spriteNames) n: _asset(n)});

void _fatal(String msg) {
  logf('fatal: $msg');
  using((a) => MessageBoxW(0, wstr(msg, a), wstr('Dartty', a), MB_ICONERROR));
  exit(1);
}

/// Точка входа для Windows.
Future<void> runDartty(List<String> args) async {
  try {
    if (args.contains('--selfcheck')) exit(_selfCheck());

    // Чёткая картинка на экранах с масштабом 125–200%.
    final setCtx = SetProcessDpiAwarenessContext;
    if (setCtx != null) {
      setCtx(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    } else {
      SetProcessDPIAware();
    }

    // Только один Dartty одновременно (то же имя мьютекса, что у Go-версии).
    // GetLastError после CreateMutexW ненадёжен: Dart VM может затереть его между вызовами FFI,
    // поэтому сначала пробуем открыть существующий мьютекс и ищем окно управления.
    if (_anotherInstance()) {
      using((a) {
        final h = FindWindowW(wstr(_ctlClass, a), nullptr);
        if (h != 0) PostMessageW(h, _wmUnhide, 0, 0);
      });
      exit(0);
    }

    // Единственный await: фоновый изолят запускаем до создания окон.
    try {
      _worker = await Worker.start();
    } catch (e) {
      logf('фоновый изолят не запустился: $e');
    }
    _runWindows(args);
  } catch (e, st) {
    logf('fatal: $e\n$st');
    _fatal('Dartty не смог запуститься: $e');
  }
  exit(0);
}

const _mutexName = r'Local\DarttyMascotMutex';

bool _anotherInstance() => using((a) {
      final name = wstr(_mutexName, a);
      final existing = OpenMutexW(SYNCHRONIZE, 0, name);
      if (existing != 0) {
        CloseHandle(existing);
        return true;
      }
      if (FindWindowW(wstr(_ctlClass, a), nullptr) != 0) return true;
      // Создаём свой и сразу владеем им: второй Dart-экземпляр, запущенный в ту же
      // секунду, получит WAIT_TIMEOUT. Дескриптор живёт до конца процесса.
      final mine = CreateMutexW(nullptr, 1, name);
      return mine == 0 || WaitForSingleObject(mine, 0) == WAIT_TIMEOUT;
    });

/// Синхронная часть: окна и цикл сообщений. Отсюда не возвращаемся в event loop,
/// поэтому весь GUI-код всегда на одном потоке ОС.
void _runWindows(List<String> args) {
  _threadId = GetCurrentThreadId();
  _stats = args.contains('--stats');
  timeBeginPeriod(1);
  final exePath = Platform.resolvedExecutable;
  _hInst = GetModuleHandleW(nullptr);

  final bank = loadSprites();
  final cxs = GetSystemMetrics(SM_CXSMICON), cys = GetSystemMetrics(SM_CYSMICON);
  _trayIcon = iconFromIco(_asset('icon_tray'), cxs, cys);
  _bigIcon = iconFromIco(_asset('icon_app'), GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON));
  _cursorHand = LoadCursorW(0, IDC_HAND);
  _cursorMove = LoadCursorW(0, IDC_SIZEALL);
  final arrow = LoadCursorW(0, IDC_ARROW);

  final wndProc = NativeCallable<WNDPROC>.isolateLocal(_wndProc, exceptionalReturn: 0);
  final layerClass = wstr(_layerClass), ctlClass = wstr(_ctlClass);
  for (final cls in [ctlClass, layerClass]) {
    final wc = mem<WNDCLASSEXW>();
    wc.ref
      ..cbSize = sizeOf<WNDCLASSEXW>()
      ..lpfnWndProc = wndProc.nativeFunction
      ..hInstance = _hInst
      ..hIcon = _bigIcon
      ..hCursor = arrow
      ..lpszClassName = cls
      ..hIconSm = _trayIcon;
    RegisterClassExW(wc);
    mem.free(wc);
  }

  int layered(String title) => using((a) => CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
      layerClass,
      wstr(title, a),
      WS_POPUP,
      0,
      0,
      1,
      1,
      0,
      0,
      _hInst,
      nullptr));

  _ctl = using((a) =>
      CreateWindowExW(WS_EX_TOOLWINDOW, ctlClass, wstr('Dartty', a), WS_POPUP, 0, 0, 0, 0, 0, 0, _hInst, nullptr));
  _bugWin.hwnd = layered('Dartty Bug');
  _mascotWin.hwnd = layered('Dartty');
  _bubbleWin.hwnd = layered('Dartty Speech');
  if (_ctl == 0 || _mascotWin.hwnd == 0) _fatal('Не удалось создать окно Dartty');

  final settings = loadSettings();
  _world = WinWorld(isOwn: _isOwn, onNotify: _notify, onQuit: _quit, exePath: exePath);
  _app = App(_world, settings, bank);
  if (settings.autostart && !args.contains('--no-autostart')) _world.setAutostart(true);

  _msgTaskbarCreated = using((a) => RegisterWindowMessageW(wstr('TaskbarCreated', a)));
  _addTray();
  _updateTrayTip();

  // Запасной таймер: кадры, пока открыто меню (модальный цикл Windows).
  SetTimer(_ctl, 1, 16, nullptr);
  _worker?.attach(_ctl, _wmWorker);
  _worker?.request(1, 'ping', 'мост GUI ↔ фоновый изолят работает');
  logf('started $exePath (Dart ${Platform.version.split(' ').first})');

  _loop();
  _removeTray();
}

/// 60 кадров в секунду: сообщения → кадр → сон до следующего кадра или до ввода.
///
/// Спим на таймере высокого разрешения: в Windows 11 timeBeginPeriod может не
/// действовать, и обычный таймаут просыпается по сетке 15,6 мс (было ~40 к/с).
void _loop() {
  final msg = mem<MSG>();
  const frameDt = 1 / 60;
  final timer = CreateWaitableTimerExW(nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
  if (timer == 0) logf('нет таймера высокого разрешения, кадры будут по timeBeginPeriod');
  final handles = mem<IntPtr>()..value = timer;
  final due = mem<Int64>();
  var next = _t;
  while (!_quitting) {
    while (PeekMessageW(msg, 0, 0, 0, PM_REMOVE) != 0) {
      if (msg.ref.message == WM_QUIT) {
        _quitting = true;
        break;
      }
      TranslateMessage(msg);
      DispatchMessageW(msg);
    }
    if (_quitting) break;
    final t = _t;
    if (t >= next - 0.0005) {
      _onFrame();
      next += frameDt;
      if (next < t) next = t + frameDt; // после долгой паузы не догоняем пропущенные кадры
    }
    final wait = next - _t;
    if (wait <= 0.0002) continue;
    if (timer != 0) {
      due.value = -(wait * 1e7).round(); // относительное время в единицах 100 нс
      SetWaitableTimer(timer, due, 0, nullptr, nullptr, 0);
      MsgWaitForMultipleObjectsEx(1, handles, INFINITE, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
    } else {
      MsgWaitForMultipleObjectsEx(0, nullptr, (wait * 1000).floor(), QS_ALLINPUT, MWMO_INPUTAVAILABLE);
    }
  }
}

void _quit() {
  if (_quitting) return;
  _quitting = true;
  _app.persist();
  _removeTray();
  logf('exit');
  PostQuitMessage(0);
}

/// Проверка собранного exe без окон: картинки читаются, кадр рисуется.
int _selfCheck() {
  try {
    final bank = loadSprites();
    for (final n in ['icon_app', 'icon_tray']) {
      if (_asset(n).length < 100) throw StateError('нет иконки $n');
    }
    final img = Img(300, 300);
    drawImage(img, bank.get('idle', 0.5), Affine.identity);
    var opaque = 0;
    for (var i = 3; i < img.pix.length; i += 4) {
      if (img.pix[i] > 128) opaque++;
    }
    if (opaque < 1000) throw StateError('кадр пустой');
    logf('selfcheck ok: ${spriteNames.length} спрайтов');
    return 0;
  } catch (e) {
    logf('selfcheck failed: $e');
    return 3;
  }
}
