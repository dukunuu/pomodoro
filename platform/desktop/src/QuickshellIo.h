#pragma once

// Emulation of the Quickshell.Io types that the shared service uses.
//
// Service.qml is the same file that runs as an Omarchy Quickshell plugin, so
// rather than rewriting it for the desktop hosts this module registers types
// with the same names and the same API under the QML module URI
// "Quickshell.Io". On Linux/Omarchy the real Quickshell provides them; here
// they are backed by QProcess, QFile, and QFileSystemWatcher.

#include <QFileSystemWatcher>
#include <QProcess>
#include <QStringList>
#include <QVariant>

#include <QtQml/qqmlregistration.h>

// The Windows CRT exposes stdout/stderr as macros. They collide with the
// Quickshell property names used by the shared service, so keep those names
// visible to moc and QML.
#ifdef stdout
#undef stdout
#endif
#ifdef stderr
#undef stderr
#endif

class DesktopStream : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString text READ text NOTIFY textChanged)
    Q_PROPERTY(bool waitForEnd READ waitForEnd WRITE setWaitForEnd)

public:
    explicit DesktopStream(QObject *parent = nullptr);

    QString text() const;
    bool waitForEnd() const;
    void setWaitForEnd(bool value);

    void reset();
    void consume(const QByteArray &data);
    void finish();

protected:
    void setSplitLines(bool value);

signals:
    void textChanged();
    void read(const QString &line);
    void streamFinished();

private:
    bool m_waitForEnd = false;
    bool m_splitLines = false;
    QString m_text;
    QByteArray m_pending;
};

class DesktopSplitParser : public DesktopStream
{
    Q_OBJECT
    QML_NAMED_ELEMENT(SplitParser)

public:
    explicit DesktopSplitParser(QObject *parent = nullptr);
};

class DesktopStdioCollector : public DesktopStream
{
    Q_OBJECT
    QML_NAMED_ELEMENT(StdioCollector)

public:
    explicit DesktopStdioCollector(QObject *parent = nullptr);
};

class DesktopProcess : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Process)
    Q_PROPERTY(QStringList command READ command WRITE setCommand NOTIFY commandChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(QObject *stdout READ stdoutDevice WRITE setStdoutDevice NOTIFY streamsChanged)
    Q_PROPERTY(QObject *stderr READ stderrDevice WRITE setStderrDevice NOTIFY streamsChanged)

public:
    explicit DesktopProcess(QObject *parent = nullptr);

    QStringList command() const;
    void setCommand(const QStringList &command);
    bool running() const;
    void setRunning(bool running);
    QObject *stdoutDevice() const;
    void setStdoutDevice(QObject *device);
    QObject *stderrDevice() const;
    void setStderrDevice(QObject *device);

signals:
    void commandChanged();
    void runningChanged();
    void streamsChanged();
    void exited(int exitCode);

private:
    void startProcess();
    void complete(int exitCode);
    void resetStreams();
    void consumeOutput(QObject *device, const QByteArray &data);
    void finishStream(QObject *device);

    QStringList m_command;
    bool m_running = false;
    QObject *m_stdoutDevice = nullptr;
    QObject *m_stderrDevice = nullptr;
    QProcess m_process;
};

class DesktopFileView : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(FileView)
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(bool watchChanges READ watchChanges WRITE setWatchChanges)
    Q_PROPERTY(bool atomicWrites READ atomicWrites WRITE setAtomicWrites)
    Q_PROPERTY(bool printErrors READ printErrors WRITE setPrintErrors)

public:
    explicit DesktopFileView(QObject *parent = nullptr);

    QString path() const;
    void setPath(const QString &path);
    bool watchChanges() const;
    void setWatchChanges(bool value);
    bool atomicWrites() const;
    void setAtomicWrites(bool value);
    bool printErrors() const;
    void setPrintErrors(bool value);

    Q_INVOKABLE QString text() const;
    Q_INVOKABLE void reload();
    Q_INVOKABLE void setText(const QString &value);

signals:
    void pathChanged();
    void loaded();
    void loadFailed();
    void fileChanged();

private:
    void updateWatcher();
    void onWatchedFileChanged(const QString &path);

    QString m_path;
    QString m_text;
    bool m_watchChanges = false;
    bool m_atomicWrites = false;
    bool m_printErrors = true;
    QFileSystemWatcher m_watcher;
};

// Quickshell exposes the running shell over an IPC socket so `qs ipc call ...`
// can drive it. The desktop hosts have no shell to talk to, but Service.qml
// declares its IPC surface unconditionally, so provide the element and let the
// declared functions exist without a transport behind them.
class DesktopIpcHandler : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(IpcHandler)
    Q_PROPERTY(QString target READ target WRITE setTarget NOTIFY targetChanged)

public:
    explicit DesktopIpcHandler(QObject *parent = nullptr);

    QString target() const;
    void setTarget(const QString &target);

signals:
    void targetChanged();

private:
    QString m_target;
};
