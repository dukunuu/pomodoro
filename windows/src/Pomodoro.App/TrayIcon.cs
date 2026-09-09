using System.Runtime.InteropServices;

namespace Pomodoro.App;

/// <summary>
/// A notification-area icon with a live countdown tooltip and a context menu.
/// WinUI has no tray control, so this talks to Shell_NotifyIcon directly
/// through a message-only window.
/// </summary>
public sealed class TrayIcon : IDisposable
{
    private const int WmApp = 0x8000;
    private const int TrayCallback = WmApp + 1;
    private const int WmLButtonUp = 0x0202;
    private const int WmRButtonUp = 0x0205;
    private const int WmDestroy = 0x0002;
    private const int WmCommand = 0x0111;

    private const int NimAdd = 0x0000;
    private const int NimModify = 0x0001;
    private const int NimDelete = 0x0002;
    private const int NifMessage = 0x0001;
    private const int NifIcon = 0x0002;
    private const int NifTip = 0x0004;

    private const int MfString = 0x0000;
    private const int MfSeparator = 0x0800;
    private const int TpmReturnCmd = 0x0100;
    private const int TpmRightButton = 0x0002;

    private const int IdOpen = 1;
    private const int IdToggle = 2;
    private const int IdSkip = 3;
    private const int IdReset = 4;
    private const int IdQuit = 5;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public int cbSize;
        public IntPtr hWnd;
        public int uID;
        public int uFlags;
        public int uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;
        public int dwState;
        public int dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szInfo;
        public int uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string szInfoTitle;
        public int dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WndClassEx
    {
        public int cbSize;
        public int style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    private delegate IntPtr WndProc(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassEx(ref WndClassEx wndClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(
        int exStyle, string className, string? windowName, int style,
        int x, int y, int width, int height,
        IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyWindow(IntPtr hwnd);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool Shell_NotifyIcon(int message, ref NotifyIconData data);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern uint ExtractIconEx(
        string file, int index, out IntPtr large, out IntPtr small, uint icons);

    [DllImport("user32.dll")]
    private static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool AppendMenu(IntPtr menu, int flags, int id, string? item);

    [DllImport("user32.dll")]
    private static extern bool DestroyMenu(IntPtr menu);

    [DllImport("user32.dll")]
    private static extern int TrackPopupMenuEx(
        IntPtr menu, int flags, int x, int y, IntPtr hwnd, IntPtr overlay);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? name);

    private readonly WndProc _proc;
    private IntPtr _hwnd;
    private IntPtr _icon;
    private bool _added;
    private string _tip = "Pomodoro";

    /// <summary>Raised on the UI thread's behalf; handlers must marshal.</summary>
    public event Action? OpenRequested;
    public event Action? ToggleRequested;
    public event Action? SkipRequested;
    public event Action? ResetRequested;
    public event Action? QuitRequested;

    public TrayIcon()
    {
        // The delegate must outlive the window or the callback tears down.
        _proc = HandleMessage;
        Create();
    }

    private void Create()
    {
        var instance = GetModuleHandle(null);
        var className = "PomodoroTrayWindow";
        var wndClass = new WndClassEx
        {
            cbSize = Marshal.SizeOf<WndClassEx>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_proc),
            hInstance = instance,
            lpszClassName = className
        };
        RegisterClassEx(ref wndClass);

        // HWND_MESSAGE (-3): a message-only window, never shown.
        _hwnd = CreateWindowEx(0, className, null, 0, 0, 0, 0, 0, new IntPtr(-3),
            IntPtr.Zero, instance, IntPtr.Zero);
        if (_hwnd == IntPtr.Zero) return;

        var exe = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(exe))
        {
            ExtractIconEx(exe, 0, out var large, out var small, 1);
            _icon = small != IntPtr.Zero ? small : large;
        }

        var data = NewData();
        data.uFlags = NifMessage | NifIcon | NifTip;
        _added = Shell_NotifyIcon(NimAdd, ref data);
    }

    private NotifyIconData NewData() => new()
    {
        cbSize = Marshal.SizeOf<NotifyIconData>(),
        hWnd = _hwnd,
        uID = 1,
        uCallbackMessage = TrayCallback,
        hIcon = _icon,
        szTip = _tip,
        szInfo = string.Empty,
        szInfoTitle = string.Empty
    };

    /// <summary>The countdown lives in the tooltip; Windows has no text tray item.</summary>
    public void SetTooltip(string text)
    {
        if (!_added) return;
        _tip = text.Length <= 127 ? text : text[..127];
        var data = NewData();
        data.uFlags = NifTip;
        Shell_NotifyIcon(NimModify, ref data);
    }

    private IntPtr HandleMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam)
    {
        switch (message)
        {
            case TrayCallback:
                var mouse = lParam.ToInt32();
                if (mouse == WmLButtonUp) OpenRequested?.Invoke();
                else if (mouse == WmRButtonUp) ShowMenu();
                return IntPtr.Zero;

            case WmCommand:
                Dispatch(wParam.ToInt32() & 0xFFFF);
                return IntPtr.Zero;

            case WmDestroy:
                Remove();
                return IntPtr.Zero;
        }
        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    private void ShowMenu()
    {
        var menu = CreatePopupMenu();
        if (menu == IntPtr.Zero) return;
        try
        {
            AppendMenu(menu, MfString, IdOpen, "Open dashboard");
            AppendMenu(menu, MfString, IdToggle, "Start / pause");
            AppendMenu(menu, MfString, IdSkip, "Skip phase");
            AppendMenu(menu, MfString, IdReset, "Reset phase");
            AppendMenu(menu, MfSeparator, 0, null);
            AppendMenu(menu, MfString, IdQuit, "Quit Pomodoro");

            GetCursorPos(out var point);
            // Required, or the menu will not dismiss when focus moves away.
            SetForegroundWindow(_hwnd);
            var chosen = TrackPopupMenuEx(
                menu, TpmReturnCmd | TpmRightButton, point.X, point.Y, _hwnd, IntPtr.Zero);
            if (chosen != 0) Dispatch(chosen);
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    private void Dispatch(int command)
    {
        switch (command)
        {
            case IdOpen: OpenRequested?.Invoke(); break;
            case IdToggle: ToggleRequested?.Invoke(); break;
            case IdSkip: SkipRequested?.Invoke(); break;
            case IdReset: ResetRequested?.Invoke(); break;
            case IdQuit: QuitRequested?.Invoke(); break;
        }
    }

    private void Remove()
    {
        if (!_added) return;
        var data = NewData();
        Shell_NotifyIcon(NimDelete, ref data);
        _added = false;
    }

    public void Dispose()
    {
        Remove();
        if (_hwnd != IntPtr.Zero)
        {
            DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }
    }
}
