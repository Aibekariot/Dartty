// Реализация World для Windows: окна, мониторы, курсор, текст через GDI, автозапуск.

import 'dart:ffi';
import 'dart:typed_data';

import '../world.dart';
import 'ffi.dart';
import 'win32.dart';

class WinWorld implements World {
  final bool Function(int h) isOwn;
  final void Function(String title, String text) onNotify;
  final void Function() onQuit;
  final String exePath;

  WinWorld({required this.isOwn, required this.onNotify, required this.onQuit, required this.exePath});

  // Постоянные буферы: вызовы идут каждый кадр, не выделяем память зря.
  final _pt = mem<POINT>();
  final _mi = mem<MONITORINFO>();
  final _rect = mem<RECT>();
  final _lii = mem<LASTINPUTINFO>();
  final _buf = mem<Uint16>(1024);
  final _u32 = mem<Uint32>();
  final _i32 = mem<Int32>();
  String _lastProc = '', _lastTitle = '';

  final _enumList = <WinInfo>[];
  late final _enumCb = NativeCallable<WNDENUMPROC>.isolateLocal(_enumProc, exceptionalReturn: 1);

  @override
  double dpi() {
    final f = GetDpiForSystem;
    if (f != null) {
      final d = f();
      if (d > 0) return d / 96;
    }
    return 1;
  }

  @override
  (double, double) cursor() {
    GetCursorPos(_pt);
    return (_pt.ref.x.toDouble(), _pt.ref.y.toDouble());
  }

  (RECT, RECT) _monitorAt(int x, int y) {
    final hm = MonitorFromPoint(packPoint(x, y), MONITOR_DEFAULTTONEAREST);
    _mi.ref.cbSize = sizeOf<MONITORINFO>();
    GetMonitorInfoW(hm, _mi);
    return (_mi.ref.rcWork, _mi.ref.rcMonitor);
  }

  @override
  Rect4 workArea(double x, double y) {
    final (w, _) = _monitorAt(x.toInt(), y.toInt());
    return (l: w.left.toDouble(), t: w.top.toDouble(), r: w.right.toDouble(), b: w.bottom.toDouble());
  }

  /// Границы окна без невидимой рамки-тени (DWM), иначе GetWindowRect.
  bool _windowRect(int h) {
    if (DwmGetWindowAttribute(h, DWMWA_EXTENDED_FRAME_BOUNDS, _rect, sizeOf<RECT>()) == 0) return true;
    return GetWindowRect(h, _rect) != 0;
  }

  bool _isCloaked(int h) => DwmGetWindowAttribute(h, DWMWA_CLOAKED, _u32, 4) == 0 && _u32.value != 0;

  String windowText(int h) => fromWstr(_buf, GetWindowTextW(h, _buf, 512));

  String className(int h) => fromWstr(_buf, GetClassNameW(h, _buf, 256));

  static const _skipClasses = {
    'Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd', 'Windows.UI.Core.CoreWindow', //
    'ApplicationFrameWindow_Hidden', 'NotifyIconOverflowWindow', 'TopLevelWindowForOverflowXamlIsland',
  };

  int _enumProc(int h, int lp) {
    if (isOwn(h) || IsWindowVisible(h) == 0 || IsIconic(h) != 0 || _isCloaked(h)) return 1;
    if ((GetWindowLongPtrW(h, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) return 1;
    if (_skipClasses.contains(className(h))) return 1;
    if (windowText(h).isEmpty) return 1;
    if (!_windowRect(h)) return 1;
    final r = _rect.ref;
    if (r.right - r.left < 120 || r.bottom - r.top < 80) return 1;
    _enumList.add(WinInfo(h, r.left.toDouble(), r.top.toDouble(), r.right.toDouble(), r.bottom.toDouble(),
        zoomed: IsZoomed(h) != 0));
    return 1;
  }

  @override
  List<WinInfo> candidateWindows() {
    _enumList.clear();
    EnumWindows(_enumCb.nativeFunction, 0);
    return List.of(_enumList);
  }

  @override
  WinInfo? windowAlive(int h) {
    if (h == 0 || IsWindow(h) == 0 || IsWindowVisible(h) == 0 || IsIconic(h) != 0 || _isCloaked(h)) return null;
    if (!_windowRect(h)) return null;
    final r = _rect.ref;
    return WinInfo(h, r.left.toDouble(), r.top.toDouble(), r.right.toDouble(), r.bottom.toDouble(),
        zoomed: IsZoomed(h) != 0);
  }

  @override
  int rootAt(double x, double y) {
    final h = WindowFromPoint(packPoint(x.toInt(), y.toInt()));
    return h == 0 ? 0 : GetAncestor(h, GA_ROOT);
  }

  @override
  bool ownWindow(int h) => isOwn(h);

  /// Сколько секунд пользователь ничего не нажимал и не двигал мышь.
  @override
  double idleSeconds() {
    _lii.ref.cbSize = sizeOf<LASTINPUTINFO>();
    GetLastInputInfo(_lii);
    return ((GetTickCount() - _lii.ref.dwTime) & 0xffffffff) / 1000;
  }

  @override
  (String, String) foreground() {
    final h = GetForegroundWindow();
    if (h == 0 || isOwn(h)) return (_lastProc, _lastTitle);
    _lastProc = _processName(h);
    _lastTitle = windowText(h);
    return (_lastProc, _lastTitle);
  }

  String _processName(int h) {
    _u32.value = 0;
    GetWindowThreadProcessId(h, _u32);
    final pid = _u32.value;
    if (pid == 0) return '';
    final ph = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
    if (ph == 0) return '';
    try {
      _u32.value = 1024;
      if (QueryFullProcessImageNameW(ph, 0, _buf, _u32) == 0) return '';
      return fromWstr(_buf, _u32.value);
    } finally {
      CloseHandle(ph);
    }
  }

  /// Игра / видео / презентация на весь экран — Dartty прячется.
  @override
  bool fullscreen() {
    if (SHQueryUserNotificationState(_i32) != 0) return false;
    switch (_i32.value) {
      case 3 || 4: // D3D-игра на весь экран, режим презентации
        return true;
      case 2: // «занят»: проверяем, что активное окно и правда на весь монитор
        return _foregroundCoversMonitor();
    }
    return false;
  }

  bool _foregroundCoversMonitor() {
    final h = GetForegroundWindow();
    if (h == 0) return false;
    if (const {'Progman', 'WorkerW', 'Shell_TrayWnd'}.contains(className(h))) return false;
    if (GetWindowRect(h, _rect) == 0) return false;
    final l = _rect.ref.left, t = _rect.ref.top, r = _rect.ref.right, b = _rect.ref.bottom;
    final (_, mon) = _monitorAt((l + r) ~/ 2, (t + b) ~/ 2);
    return l <= mon.left && t <= mon.top && r >= mon.right && b >= mon.bottom;
  }

  /// Текст белым по чёрному через GDI; яркость пикселя — маска покрытия.
  @override
  TextBlock renderText(String text, {required bool bold, required int px, required int maxW}) => using((a) {
        final dc = CreateCompatibleDC(0);
        final font = CreateFontW(-px, 0, 0, 0, bold ? FW_BOLD : FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
            ANTIALIASED_QUALITY, 0, wstr('Segoe UI', a));
        final oldFont = SelectObject(dc, font);
        try {
          final txt = wstr(text, a);
          final r = a<RECT>();
          r.ref.right = maxW;
          DrawTextW(dc, txt, -1, r, DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX);
          final w = r.ref.right + 2, h = r.ref.bottom + 2;
          if (w < 2 || h < 2) return TextBlock.empty;
          final bmi = a<BITMAPINFOHEADER>(2); // + запас под палитру BITMAPINFO
          bmi.ref
            ..biSize = sizeOf<BITMAPINFOHEADER>()
            ..biWidth = w
            ..biHeight = -h
            ..biPlanes = 1
            ..biBitCount = 32;
          final bitsOut = a<Pointer<Uint8>>();
          final bmp = CreateDIBSection(dc, bmi, 0, bitsOut, 0, 0);
          if (bmp == 0 || bitsOut.value.address == 0) return TextBlock.empty;
          final oldBmp = SelectObject(dc, bmp);
          try {
            SetTextColor(dc, 0x00FFFFFF);
            SetBkMode(dc, TRANSPARENT);
            final r2 = a<RECT>();
            r2.ref
              ..left = 1
              ..top = 1
              ..right = w - 1
              ..bottom = h - 1;
            DrawTextW(dc, txt, -1, r2, DT_WORDBREAK | DT_NOPREFIX);
            GdiFlush();
            final src = bitsOut.value.asTypedList(w * h * 4);
            final cov = Uint8List(w * h);
            for (var i = 0; i < w * h; i++) {
              var m = src[i * 4];
              if (src[i * 4 + 1] > m) m = src[i * 4 + 1];
              if (src[i * 4 + 2] > m) m = src[i * 4 + 2];
              cov[i] = m;
            }
            return TextBlock(cov, w, h);
          } finally {
            SelectObject(dc, oldBmp);
            DeleteObject(bmp);
          }
        } finally {
          SelectObject(dc, oldFont);
          DeleteObject(font);
          DeleteDC(dc);
        }
      });

  static const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';

  @override
  void setAutostart(bool on) => using((a) {
        final hk = a<IntPtr>();
        if (RegOpenKeyExW(HKEY_CURRENT_USER, wstr(_runKey, a), 0, KEY_SET_VALUE | KEY_QUERY_VALUE, hk) != 0) return;
        try {
          final name = wstr('Dartty', a);
          if (on) {
            final value = '"$exePath"';
            final v = wstr(value, a);
            RegSetValueExW(hk.value, name, 0, REG_SZ, v.cast<Uint8>(), (value.length + 1) * 2);
          } else {
            RegDeleteValueW(hk.value, name);
          }
        } finally {
          RegCloseKey(hk.value);
        }
      });

  @override
  void notify(String title, String text) => onNotify(title, text);

  @override
  void quit() => onQuit();
}
