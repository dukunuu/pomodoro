using System.Runtime.InteropServices;

namespace Pomodoro.App;

/// <summary>
/// Phase progress drawn on the taskbar button, so a glance at the taskbar
/// shows how far through the phase you are without raising a window. This is
/// the Windows counterpart of the Dock tile progress on macOS.
/// </summary>
public static class TaskbarProgress
{
    private enum State
    {
        NoProgress = 0,
        Indeterminate = 1,
        Normal = 2,
        Error = 4,
        Paused = 8
    }

    [ComImport]
    [Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eefaf")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ITaskbarList3
    {
        // ITaskbarList
        void HrInit();
        void AddTab(IntPtr hwnd);
        void DeleteTab(IntPtr hwnd);
        void ActivateTab(IntPtr hwnd);
        void SetActiveAlt(IntPtr hwnd);

        // ITaskbarList2
        void MarkFullscreenWindow(IntPtr hwnd, [MarshalAs(UnmanagedType.Bool)] bool fullscreen);

        // ITaskbarList3 — only the two progress members are used; the rest of
        // the vtable must still be declared so the slots line up.
        void SetProgressValue(IntPtr hwnd, ulong completed, ulong total);
        void SetProgressState(IntPtr hwnd, State state);
    }

    [ComImport]
    [Guid("56fdf344-fd6d-11d0-958a-006097c9a090")]
    [ClassInterface(ClassInterfaceType.None)]
    private class TaskbarInstance;

    private static ITaskbarList3? _taskbar;
    private static bool _unavailable;

    private static ITaskbarList3? Instance()
    {
        if (_unavailable) return null;
        if (_taskbar is not null) return _taskbar;
        try
        {
            var instance = (ITaskbarList3)new TaskbarInstance();
            instance.HrInit();
            _taskbar = instance;
            return _taskbar;
        }
        catch (Exception)
        {
            // Progress is a nicety; never let its absence break the timer.
            _unavailable = true;
            return null;
        }
    }

    public static void Update(IntPtr hwnd, double progress, bool active, bool overtime)
    {
        if (hwnd == IntPtr.Zero) return;
        var taskbar = Instance();
        if (taskbar is null) return;

        try
        {
            if (!active)
            {
                taskbar.SetProgressState(hwnd, State.NoProgress);
                return;
            }
            var clamped = Math.Max(0, Math.Min(1, progress));
            taskbar.SetProgressState(hwnd, overtime ? State.Error : State.Normal);
            taskbar.SetProgressValue(hwnd, (ulong)(clamped * 1000), 1000);
        }
        catch (COMException)
        {
            _unavailable = true;
        }
    }
}
