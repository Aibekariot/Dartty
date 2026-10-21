// Собственные FFI-привязки Win32 (только то, что нужно Dartty).
// Имена функций, структур и констант — как в документации Microsoft.

import 'dart:ffi';

final _user32 = DynamicLibrary.open('user32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _shell32 = DynamicLibrary.open('shell32.dll');
final _advapi32 = DynamicLibrary.open('advapi32.dll');
final _dwmapi = DynamicLibrary.open('dwmapi.dll');
final _winmm = DynamicLibrary.open('winmm.dll');

// ---------- Структуры ----------

final class POINT extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class SIZE extends Struct {
  @Int32()
  external int cx;
  @Int32()
  external int cy;
}

final class RECT extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class MSG extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int message;
  @IntPtr()
  external int wParam;
  @IntPtr()
  external int lParam;
  @Uint32()
  external int time;
  external POINT pt;
  @Uint32()
  external int lPrivate;
}

typedef WNDPROC = IntPtr Function(IntPtr hwnd, Uint32 msg, IntPtr wParam, IntPtr lParam);
typedef WNDENUMPROC = Int32 Function(IntPtr hwnd, IntPtr lParam);

final class WNDCLASSEXW extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int style;
  external Pointer<NativeFunction<WNDPROC>> lpfnWndProc;
  @Int32()
  external int cbClsExtra;
  @Int32()
  external int cbWndExtra;
  @IntPtr()
  external int hInstance;
  @IntPtr()
  external int hIcon;
  @IntPtr()
  external int hCursor;
  @IntPtr()
  external int hbrBackground;
  external Pointer<Uint16> lpszMenuName;
  external Pointer<Uint16> lpszClassName;
  @IntPtr()
  external int hIconSm;
}

final class BLENDFUNCTION extends Struct {
  @Uint8()
  external int BlendOp;
  @Uint8()
  external int BlendFlags;
  @Uint8()
  external int SourceConstantAlpha;
  @Uint8()
  external int AlphaFormat;
}

final class BITMAPINFOHEADER extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

final class GUID extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

final class NOTIFYICONDATAW extends Struct {
  @Uint32()
  external int cbSize;
  @IntPtr()
  external int hWnd;
  @Uint32()
  external int uID;
  @Uint32()
  external int uFlags;
  @Uint32()
  external int uCallbackMessage;
  @IntPtr()
  external int hIcon;
  @Array(128)
  external Array<Uint16> szTip;
  @Uint32()
  external int dwState;
  @Uint32()
  external int dwStateMask;
  @Array(256)
  external Array<Uint16> szInfo;
  @Uint32()
  external int uVersion;
  @Array(64)
  external Array<Uint16> szInfoTitle;
  @Uint32()
  external int dwInfoFlags;
  external GUID guidItem;
  @IntPtr()
  external int hBalloonIcon;
}

final class MONITORINFO extends Struct {
  @Uint32()
  external int cbSize;
  external RECT rcMonitor;
  external RECT rcWork;
  @Uint32()
  external int dwFlags;
}

final class LASTINPUTINFO extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int dwTime;
}

// ---------- Константы ----------

const WS_POPUP = 0x80000000;
const WS_EX_LAYERED = 0x00080000;
const WS_EX_TOOLWINDOW = 0x00000080;
const WS_EX_TOPMOST = 0x00000008;
const WS_EX_NOACTIVATE = 0x08000000;
const WS_EX_TRANSPARENT = 0x00000020;
const GWL_EXSTYLE = -20;
const SW_HIDE = 0;
const SW_SHOWNOACTIVATE = 4;
const SWP_NOSIZE = 0x0001;
const SWP_NOMOVE = 0x0002;
const SWP_NOZORDER = 0x0004;
const SWP_NOACTIVATE = 0x0010;
const HWND_TOPMOST = -1;
const ULW_ALPHA = 2;
const AC_SRC_ALPHA = 1;
const WM_NULL = 0x0000;
const WM_CLOSE = 0x0010;
const WM_QUIT = 0x0012;
const WM_SETCURSOR = 0x0020;
const WM_MOUSEACTIVATE = 0x0021;
const WM_TIMER = 0x0113;
const WM_MOUSEMOVE = 0x0200;
const WM_LBUTTONDOWN = 0x0201;
const WM_LBUTTONUP = 0x0202;
const WM_RBUTTONUP = 0x0205;
const WM_CAPTURECHANGED = 0x0215;
const WM_APP = 0x8000;
const MA_NOACTIVATE = 3;
const PM_REMOVE = 0x0001;
const QS_ALLINPUT = 0x04FF;
const MWMO_INPUTAVAILABLE = 0x0004;
const IDC_ARROW = 32512;
const IDC_HAND = 32649;
const IDC_SIZEALL = 32646;
const MF_STRING = 0x0000;
const MF_GRAYED = 0x0001;
const MF_CHECKED = 0x0008;
const MF_POPUP = 0x0010;
const MF_SEPARATOR = 0x0800;
const MF_RADIOCHECK = 0x0200;
const TPM_RIGHTBUTTON = 0x0002;
const TPM_RETURNCMD = 0x0100;
const TPM_BOTTOMALIGN = 0x0020;
const NIM_ADD = 0;
const NIM_MODIFY = 1;
const NIM_DELETE = 2;
const NIF_MESSAGE = 0x01;
const NIF_ICON = 0x02;
const NIF_TIP = 0x04;
const NIF_INFO = 0x10;
const NIIF_INFO = 0x01;
const GA_ROOT = 2;
const MONITOR_DEFAULTTONEAREST = 2;
const DT_WORDBREAK = 0x0010;
const DT_CALCRECT = 0x0400;
const DT_NOPREFIX = 0x0800;
const TRANSPARENT = 1;
const ANTIALIASED_QUALITY = 4;
const FW_NORMAL = 400;
const FW_BOLD = 700;
const DEFAULT_CHARSET = 1;
const SM_CXSMICON = 49;
const SM_CYSMICON = 50;
const SM_CXICON = 11;
const SM_CYICON = 12;
const PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
const ERROR_ALREADY_EXISTS = 183;
const WAIT_TIMEOUT = 258;

/// (HKEY)(LONG)0x80000001 — со знаковым расширением, как в заголовках Windows.
const HKEY_CURRENT_USER = -0x7FFFFFFF;
const KEY_QUERY_VALUE = 0x0001;
const KEY_SET_VALUE = 0x0002;
const REG_SZ = 1;
const DWMWA_EXTENDED_FRAME_BOUNDS = 9;
const DWMWA_CLOAKED = 14;
const LR_DEFAULTCOLOR = 0;
const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4;
const MB_ICONERROR = 0x10;

// ---------- user32 ----------

final RegisterClassExW = _user32
    .lookupFunction<Uint16 Function(Pointer<WNDCLASSEXW>), int Function(Pointer<WNDCLASSEXW>)>('RegisterClassExW');
final CreateWindowExW = _user32.lookupFunction<
    IntPtr Function(
        Uint32, Pointer<Uint16>, Pointer<Uint16>, Uint32, Int32, Int32, Int32, Int32, IntPtr, IntPtr, IntPtr, Pointer),
    int Function(
        int, Pointer<Uint16>, Pointer<Uint16>, int, int, int, int, int, int, int, int, Pointer)>('CreateWindowExW');
final DefWindowProcW =
    _user32.lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr), int Function(int, int, int, int)>(
        'DefWindowProcW');
final PeekMessageW = _user32.lookupFunction<Int32 Function(Pointer<MSG>, IntPtr, Uint32, Uint32, Uint32),
    int Function(Pointer<MSG>, int, int, int, int)>('PeekMessageW');
final TranslateMessage =
    _user32.lookupFunction<Int32 Function(Pointer<MSG>), int Function(Pointer<MSG>)>('TranslateMessage');
final DispatchMessageW =
    _user32.lookupFunction<IntPtr Function(Pointer<MSG>), int Function(Pointer<MSG>)>('DispatchMessageW');
final MsgWaitForMultipleObjectsEx = _user32.lookupFunction<Uint32 Function(Uint32, Pointer, Uint32, Uint32, Uint32),
    int Function(int, Pointer, int, int, int)>('MsgWaitForMultipleObjectsEx');
final PostQuitMessage = _user32.lookupFunction<Void Function(Int32), void Function(int)>('PostQuitMessage');
final PostMessageW = _user32
    .lookupFunction<Int32 Function(IntPtr, Uint32, IntPtr, IntPtr), int Function(int, int, int, int)>('PostMessageW');
final SetTimer = _user32
    .lookupFunction<IntPtr Function(IntPtr, IntPtr, Uint32, Pointer), int Function(int, int, int, Pointer)>('SetTimer');
final ShowWindow = _user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
final SetWindowPos = _user32.lookupFunction<Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int, int)>('SetWindowPos');
final UpdateLayeredWindow = _user32.lookupFunction<
    Int32 Function(
        IntPtr, IntPtr, Pointer<POINT>, Pointer<SIZE>, IntPtr, Pointer<POINT>, Uint32, Pointer<BLENDFUNCTION>, Uint32),
    int Function(int, int, Pointer<POINT>, Pointer<SIZE>, int, Pointer<POINT>, int, Pointer<BLENDFUNCTION>,
        int)>('UpdateLayeredWindow');
final GetDC = _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
final ReleaseDC = _user32.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>('ReleaseDC');
final GetCursorPos =
    _user32.lookupFunction<Int32 Function(Pointer<POINT>), int Function(Pointer<POINT>)>('GetCursorPos');
final SetCapture = _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('SetCapture');
final ReleaseCapture = _user32.lookupFunction<Int32 Function(), int Function()>('ReleaseCapture');
final LoadCursorW = _user32.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('LoadCursorW');
final SetCursor = _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('SetCursor');
final CreatePopupMenu = _user32.lookupFunction<IntPtr Function(), int Function()>('CreatePopupMenu');
final AppendMenuW = _user32.lookupFunction<Int32 Function(IntPtr, Uint32, IntPtr, Pointer<Uint16>),
    int Function(int, int, int, Pointer<Uint16>)>('AppendMenuW');
final TrackPopupMenu = _user32.lookupFunction<Int32 Function(IntPtr, Uint32, Int32, Int32, Int32, IntPtr, Pointer),
    int Function(int, int, int, int, int, int, Pointer)>('TrackPopupMenu');
final DestroyMenu = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyMenu');
final SetForegroundWindow = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
final GetForegroundWindow = _user32.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
final GetWindowThreadProcessId =
    _user32.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>(
        'GetWindowThreadProcessId');
final GetWindowTextW =
    _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>, Int32), int Function(int, Pointer<Uint16>, int)>(
        'GetWindowTextW');
final GetClassNameW =
    _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>, Int32), int Function(int, Pointer<Uint16>, int)>(
        'GetClassNameW');
final IsWindowVisible = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');
final IsIconic = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
final IsZoomed = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsZoomed');
final IsWindow = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindow');
final EnumWindows = _user32.lookupFunction<Int32 Function(Pointer<NativeFunction<WNDENUMPROC>>, IntPtr),
    int Function(Pointer<NativeFunction<WNDENUMPROC>>, int)>('EnumWindows');
final GetWindowRect =
    _user32.lookupFunction<Int32 Function(IntPtr, Pointer<RECT>), int Function(int, Pointer<RECT>)>('GetWindowRect');

/// POINT по значению (8 байт) в x64 передаётся одним 64-битным регистром.
final WindowFromPoint = _user32.lookupFunction<IntPtr Function(Int64), int Function(int)>('WindowFromPoint');
final GetAncestor = _user32.lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('GetAncestor');
final MonitorFromPoint =
    _user32.lookupFunction<IntPtr Function(Int64, Uint32), int Function(int, int)>('MonitorFromPoint');
final GetMonitorInfoW =
    _user32.lookupFunction<Int32 Function(IntPtr, Pointer<MONITORINFO>), int Function(int, Pointer<MONITORINFO>)>(
        'GetMonitorInfoW');
final GetLastInputInfo = _user32
    .lookupFunction<Int32 Function(Pointer<LASTINPUTINFO>), int Function(Pointer<LASTINPUTINFO>)>('GetLastInputInfo');
final GetWindowLongPtrW =
    _user32.lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>('GetWindowLongPtrW');
final SetWindowLongPtrW =
    _user32.lookupFunction<IntPtr Function(IntPtr, Int32, IntPtr), int Function(int, int, int)>('SetWindowLongPtrW');
final FindWindowW = _user32.lookupFunction<IntPtr Function(Pointer<Uint16>, Pointer<Uint16>),
    int Function(Pointer<Uint16>, Pointer<Uint16>)>('FindWindowW');
final RegisterWindowMessageW =
    _user32.lookupFunction<Uint32 Function(Pointer<Uint16>), int Function(Pointer<Uint16>)>('RegisterWindowMessageW');
final SetProcessDPIAware = _user32.lookupFunction<Int32 Function(), int Function()>('SetProcessDPIAware');
final DrawTextW = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>, Int32, Pointer<RECT>, Uint32),
    int Function(int, Pointer<Uint16>, int, Pointer<RECT>, int)>('DrawTextW');
final GetSystemMetrics = _user32.lookupFunction<Int32 Function(Int32), int Function(int)>('GetSystemMetrics');
final MessageBoxW = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>, Pointer<Uint16>, Uint32),
    int Function(int, Pointer<Uint16>, Pointer<Uint16>, int)>('MessageBoxW');
final CreateIconFromResourceEx = _user32.lookupFunction<
    IntPtr Function(Pointer<Uint8>, Uint32, Int32, Uint32, Int32, Int32, Uint32),
    int Function(Pointer<Uint8>, int, int, int, int, int, int)>('CreateIconFromResourceEx');
final LookupIconIdFromDirectoryEx = _user32.lookupFunction<Int32 Function(Pointer<Uint8>, Int32, Int32, Int32, Uint32),
    int Function(Pointer<Uint8>, int, int, int, int)>('LookupIconIdFromDirectoryEx');

/// Есть только в Windows 10 1607+; на старых системах — null.
final int Function(int)? SetProcessDpiAwarenessContext = _user32.providesSymbol('SetProcessDpiAwarenessContext')
    ? _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetProcessDpiAwarenessContext')
    : null;
final int Function()? GetDpiForSystem = _user32.providesSymbol('GetDpiForSystem')
    ? _user32.lookupFunction<Uint32 Function(), int Function()>('GetDpiForSystem')
    : null;

// ---------- shell32 ----------

final Shell_NotifyIconW = _shell32.lookupFunction<Int32 Function(Uint32, Pointer<NOTIFYICONDATAW>),
    int Function(int, Pointer<NOTIFYICONDATAW>)>('Shell_NotifyIconW');
final SHQueryUserNotificationState = _shell32
    .lookupFunction<Int32 Function(Pointer<Int32>), int Function(Pointer<Int32>)>('SHQueryUserNotificationState');

// ---------- gdi32 ----------

final CreateCompatibleDC = _gdi32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('CreateCompatibleDC');
final CreateDIBSection = _gdi32.lookupFunction<
    IntPtr Function(IntPtr, Pointer<BITMAPINFOHEADER>, Uint32, Pointer<Pointer<Uint8>>, IntPtr, Uint32),
    int Function(int, Pointer<BITMAPINFOHEADER>, int, Pointer<Pointer<Uint8>>, int, int)>('CreateDIBSection');
final SelectObject = _gdi32.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('SelectObject');
final DeleteObject = _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');
final DeleteDC = _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');
final CreateFontW = _gdi32.lookupFunction<
    IntPtr Function(Int32, Int32, Int32, Int32, Int32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32,
        Pointer<Uint16>),
    int Function(int, int, int, int, int, int, int, int, int, int, int, int, int, Pointer<Uint16>)>('CreateFontW');
final SetTextColor = _gdi32.lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>('SetTextColor');
final SetBkMode = _gdi32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('SetBkMode');
final GdiFlush = _gdi32.lookupFunction<Int32 Function(), int Function()>('GdiFlush');

// ---------- kernel32 ----------

final GetModuleHandleW =
    _kernel32.lookupFunction<IntPtr Function(Pointer<Uint16>), int Function(Pointer<Uint16>)>('GetModuleHandleW');
final CreateMutexW = _kernel32.lookupFunction<IntPtr Function(Pointer, Int32, Pointer<Uint16>),
    int Function(Pointer, int, Pointer<Uint16>)>('CreateMutexW');
final WaitForSingleObject =
    _kernel32.lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>('WaitForSingleObject');
final GetLastError = _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError', isLeaf: true);
final OpenProcess =
    _kernel32.lookupFunction<IntPtr Function(Uint32, Int32, Uint32), int Function(int, int, int)>('OpenProcess');
final QueryFullProcessImageNameW = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Uint32, Pointer<Uint16>, Pointer<Uint32>),
    int Function(int, int, Pointer<Uint16>, Pointer<Uint32>)>('QueryFullProcessImageNameW');
final CloseHandle = _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final GetTickCount = _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetTickCount');
final GetCurrentThreadId = _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetCurrentThreadId');

// ---------- advapi32 ----------

final RegOpenKeyExW = _advapi32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>, Uint32, Uint32, Pointer<IntPtr>),
    int Function(int, Pointer<Uint16>, int, int, Pointer<IntPtr>)>('RegOpenKeyExW');
final RegSetValueExW = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint16>, Uint32, Uint32, Pointer<Uint8>, Uint32),
    int Function(int, Pointer<Uint16>, int, int, Pointer<Uint8>, int)>('RegSetValueExW');
final RegDeleteValueW = _advapi32
    .lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>), int Function(int, Pointer<Uint16>)>('RegDeleteValueW');
final RegCloseKey = _advapi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');

// ---------- dwmapi, winmm ----------

final DwmGetWindowAttribute =
    _dwmapi.lookupFunction<Int32 Function(IntPtr, Uint32, Pointer, Uint32), int Function(int, int, Pointer, int)>(
        'DwmGetWindowAttribute');
final timeBeginPeriod = _winmm.lookupFunction<Uint32 Function(Uint32), int Function(int)>('timeBeginPeriod');

/// Упаковка POINT для передачи по значению.
int packPoint(int x, int y) => (x & 0xffffffff) | ((y & 0xffffffff) << 32);
