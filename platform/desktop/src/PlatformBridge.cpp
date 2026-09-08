#include "PlatformBridge.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QApplication>
#include <QGuiApplication>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>
#include <QWindow>

#ifdef Q_OS_WIN
#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#endif

#include <algorithm>

namespace {

// Where the Python integration bridges live next to the running binary. macOS
// puts them in the bundle's Resources directory; the other hosts keep them
// beside the executable.
QString scriptDirectory()
{
    const QString overrideDirectory = qEnvironmentVariable("POMODORO_SCRIPT_DIR");
    if (!overrideDirectory.isEmpty())
        return QDir::cleanPath(overrideDirectory);

    const QDir applicationDir(QCoreApplication::applicationDirPath());
#ifdef Q_OS_MACOS
    // <App>.app/Contents/MacOS/<binary> -> <App>.app/Contents/Resources/scripts
    const QString bundled = QDir::cleanPath(applicationDir.filePath(QStringLiteral("../Resources/scripts")));
    if (QFileInfo::exists(bundled))
        return bundled;
#endif
    return applicationDir.filePath(QStringLiteral("scripts"));
}

QString scriptPath(const QString &name)
{
    return QDir(scriptDirectory()).filePath(name);
}

QString pythonInterpreter()
{
#ifdef Q_OS_WIN
    return qEnvironmentVariable("POMODORO_PYTHON", QStringLiteral("python.exe"));
#else
    return qEnvironmentVariable("POMODORO_PYTHON", QStringLiteral("python3"));
#endif
}

// Turns a logical command into something the host can actually spawn. A .py
// entry becomes "python3 script.py"; on Windows a .cmd entry goes through the
// command interpreter.
QStringList nativeCommand(const QStringList &command)
{
    if (command.isEmpty() || command.first().isEmpty())
        return {};

    const QString program = command.first();
    const QString suffix = QFileInfo(program).suffix().toLower();
    QStringList result;
#ifdef Q_OS_WIN
    if (suffix == QStringLiteral("cmd") || suffix == QStringLiteral("bat")) {
        result << QStringLiteral("cmd.exe") << QStringLiteral("/c") << QStringLiteral("call") << program;
        result += command.mid(1);
        return result;
    }
#endif
    if (suffix == QStringLiteral("py")) {
        result << pythonInterpreter() << program;
        result += command.mid(1);
        return result;
    }
    return command;
}

#ifndef Q_OS_WIN
// Quotes one argument for a POSIX shell, used when handing a command to a
// terminal emulator or to AppleScript's `do script`.
QString shellQuote(const QString &argument)
{
    QString escaped = argument;
    escaped.replace(QLatin1Char('\''), QStringLiteral("'\\''"));
    return QLatin1Char('\'') + escaped + QLatin1Char('\'');
}

QString shellCommandLine(const QStringList &command)
{
    QStringList quoted;
    quoted.reserve(command.size());
    for (const QString &argument : command)
        quoted << shellQuote(argument);
    return quoted.join(QLatin1Char(' '));
}
#endif

#ifdef Q_OS_MACOS
// Escapes a string for embedding in an AppleScript double-quoted literal.
QString appleScriptQuote(const QString &value)
{
    QString escaped = value;
    escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    escaped.replace(QLatin1Char('"'), QStringLiteral("\\\""));
    return QLatin1Char('"') + escaped + QLatin1Char('"');
}
#endif

#ifdef Q_OS_LINUX
QString firstAvailableProgram(const QStringList &candidates)
{
    for (const QString &candidate : candidates) {
        if (!QStandardPaths::findExecutable(candidate).isEmpty())
            return candidate;
    }
    return {};
}
#endif

} // namespace

PlatformBridge::PlatformBridge(QObject *parent)
    : QObject(parent)
{
    // Keep the Python bridges and the QML service on exactly the same per-user
    // directory, including when Qt picks a platform-specific location.
    if (qEnvironmentVariableIsEmpty("POMODORO_DATA_DIR"))
        qputenv("POMODORO_DATA_DIR", stateDirectory().toUtf8());
}

QString PlatformBridge::stateDirectory() const
{
    // Windows: %LOCALAPPDATA%\Dukunuu\Pomodoro
    // macOS:   ~/Library/Application Support/Dukunuu/Pomodoro
    // Linux:   ~/.local/share/Dukunuu/Pomodoro
    return QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
}

QString PlatformBridge::integrationCommand() const
{
#ifdef Q_OS_WIN
    return scriptPath(QStringLiteral("pomodoro_integrations.cmd"));
#else
    return scriptPath(QStringLiteral("pomodoro_integrations.py"));
#endif
}

QString PlatformBridge::whistlerImportCommand() const
{
#ifdef Q_OS_WIN
    return scriptPath(QStringLiteral("pomodoro_whistler_import.cmd"));
#else
    return scriptPath(QStringLiteral("pomodoro_whistler_import.py"));
#endif
}

QString PlatformBridge::googleAuthCommand() const
{
#ifdef Q_OS_WIN
    return scriptPath(QStringLiteral("pomodoro_google_auth.cmd"));
#else
    return scriptPath(QStringLiteral("pomodoro_google_auth.py"));
#endif
}

QString PlatformBridge::whistlerSetupCommand() const
{
#ifdef Q_OS_WIN
    return scriptPath(QStringLiteral("pomodoro_whistler_setup.cmd"));
#else
    return scriptPath(QStringLiteral("pomodoro_whistler_setup.py"));
#endif
}

QString PlatformBridge::env(const QString &name) const
{
    return qEnvironmentVariable(name.toLocal8Bit().constData());
}

void PlatformBridge::execDetached(const QStringList &command)
{
    const QStringList native = nativeCommand(command);
    if (native.isEmpty())
        return;

    QProcess::startDetached(native.first(), native.mid(1));
}

bool PlatformBridge::openCommandWindow(const QStringList &command)
{
    if (command.isEmpty() || command.first().isEmpty())
        return false;

#if defined(Q_OS_WIN)
    const QString suffix = QFileInfo(command.first()).suffix().toLower();
    if (suffix == QStringLiteral("cmd") || suffix == QStringLiteral("bat")) {
        // ShellExecute knows how to run a batch file and explicitly creates a
        // visible console. This avoids the fragile '&' quoting rules of
        // powershell.exe -Command when the install path contains spaces.
        QString parameters;
        for (const QString &argument : command.mid(1)) {
            QString escaped = argument;
            escaped.replace(QLatin1Char('"'), QStringLiteral("\\\""));
            if (!parameters.isEmpty())
                parameters += QLatin1Char(' ');
            parameters += QLatin1Char('"') + escaped + QLatin1Char('"');
        }
        const HINSTANCE result = ShellExecuteW(nullptr,
                                               L"open",
                                               reinterpret_cast<LPCWSTR>(command.first().utf16()),
                                               reinterpret_cast<LPCWSTR>(parameters.utf16()),
                                               reinterpret_cast<LPCWSTR>(QCoreApplication::applicationDirPath().utf16()),
                                               SW_SHOWNORMAL);
        if (reinterpret_cast<quintptr>(result) > 32)
            return true;
    }

    const QStringList native = nativeCommand(command);
    return !native.isEmpty()
        && QProcess::startDetached(native.first(), native.mid(1), QCoreApplication::applicationDirPath());
#elif defined(Q_OS_MACOS)
    // Terminal.app keeps the window open after the script exits, so the OAuth
    // URL and any error text stay readable.
    const QString line = shellCommandLine(nativeCommand(command));
    const QString script = QStringLiteral("tell application \"Terminal\"\nactivate\ndo script %1\nend tell")
                               .arg(appleScriptQuote(line));
    return QProcess::startDetached(QStringLiteral("osascript"), {QStringLiteral("-e"), script});
#else
    const QStringList native = nativeCommand(command);
    if (native.isEmpty())
        return false;

    // Prefer a real terminal so interactive prompts are visible. Fall back to a
    // detached process when no terminal emulator can be found.
    const QString configured = qEnvironmentVariable("TERMINAL");
    QStringList terminals;
    if (!configured.isEmpty())
        terminals << configured;
    terminals << QStringLiteral("alacritty") << QStringLiteral("ghostty") << QStringLiteral("kitty")
              << QStringLiteral("foot") << QStringLiteral("x-terminal-emulator") << QStringLiteral("xterm");
    for (const QString &terminal : std::as_const(terminals)) {
        if (QStandardPaths::findExecutable(terminal).isEmpty())
            continue;
        QStringList arguments{QStringLiteral("-e")};
        arguments += native;
        if (QProcess::startDetached(terminal, arguments))
            return true;
    }
    return QProcess::startDetached(native.first(), native.mid(1));
#endif
}

bool PlatformBridge::openPath(const QString &path)
{
    if (path.isEmpty())
        return false;

    const QFileInfo info(path);
    // Opening the data directory is expected to work on a first run, before
    // anything has written to it.
    if (info.suffix().isEmpty() && !info.exists())
        QDir().mkpath(path);

    return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void PlatformBridge::notify(const QString &title, const QString &body, const QString &urgency)
{
#ifdef Q_OS_MACOS
    // Qt routes tray messages through the notification center only for signed
    // bundles; osascript works for a locally built app as well.
    const QString script = QStringLiteral("display notification %1 with title %2")
                               .arg(appleScriptQuote(body), appleScriptQuote(title));
    if (QProcess::startDetached(QStringLiteral("osascript"), {QStringLiteral("-e"), script}))
        return;
#endif
    emit notificationRequested(title, body, urgency);
}

void PlatformBridge::playAlarm()
{
    // A phase can settle on more than one code path in the same tick. One
    // sound per phase is the intent.
    const double now = double(QDateTime::currentMSecsSinceEpoch());
    if (now - m_lastAlarmMs < 2000)
        return;
    m_lastAlarmMs = now;

#if defined(Q_OS_MACOS)
    if (QProcess::startDetached(QStringLiteral("afplay"),
                                {QStringLiteral("/System/Library/Sounds/Glass.aiff")}))
        return;
#elif defined(Q_OS_LINUX)
    const QString sound = QStringLiteral("/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga");
    if (QFile::exists(sound)) {
        const QString player = firstAvailableProgram({QStringLiteral("pw-play"), QStringLiteral("paplay")});
        if (!player.isEmpty()
            && QProcess::startDetached(player, {QStringLiteral("--media-role"), QStringLiteral("Notification"), sound}))
            return;
    }
#endif
    QApplication::beep();
}

void PlatformBridge::setTaskbarWindow(QWindow *window)
{
    m_taskbarWindow = window;
}

void PlatformBridge::setTaskbarProgress(double progress, bool active)
{
#ifdef Q_OS_WIN
    if (!m_taskbarWindow)
        return;

    const HWND handle = reinterpret_cast<HWND>(m_taskbarWindow->winId());
    if (!handle)
        return;

    const HRESULT initResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(initResult) && initResult != RPC_E_CHANGED_MODE)
        return;
    const bool shouldUninitialize = initResult == S_OK || initResult == S_FALSE;

    ITaskbarList3 *taskbar = nullptr;
    const HRESULT createResult =
        CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar));
    if (SUCCEEDED(createResult) && taskbar && SUCCEEDED(taskbar->HrInit())) {
        if (active) {
            const double clamped = std::max(0.0, std::min(1.0, progress));
            taskbar->SetProgressState(handle, TBPF_NORMAL);
            taskbar->SetProgressValue(handle, static_cast<ULONGLONG>(clamped * 1000.0), 1000);
        } else {
            taskbar->SetProgressState(handle, TBPF_NOPROGRESS);
        }
        taskbar->Release();
    }

    if (shouldUninitialize)
        CoUninitialize();
#else
    Q_UNUSED(progress);
    Q_UNUSED(active);
#endif
}
