#pragma once

#include <QFileSystemWatcher>
#include <QPointer>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QVariant>

#include <QtQml/qqmlregistration.h>

class QWindow;

// The Windows CRT exposes stdout/stderr as macros. They collide with the
// Quickshell-compatible QML property names used by the direct Service.qml
// port, so keep those names visible to moc and QML.
#ifdef stdout
#undef stdout
#endif
#ifdef stderr
#undef stderr
#endif

class PlatformBridge final : public QObject
{
    Q_OBJECT

public:
    explicit PlatformBridge(QObject *parent = nullptr);

    Q_INVOKABLE QString homeDirectory() const;
    Q_INVOKABLE QString stateDirectory() const;
    Q_INVOKABLE QString dataDirectory() const;
    Q_INVOKABLE QString integrationCommand() const;
    Q_INVOKABLE QString googleAuthCommand() const;
    Q_INVOKABLE QString whistlerSetupCommand() const;
    Q_INVOKABLE QString whistlerImportCommand() const;
    Q_INVOKABLE QString env(const QString &name) const;
    Q_INVOKABLE void execDetached(const QStringList &command);
    Q_INVOKABLE void openCommandWindow(const QStringList &command);
    Q_INVOKABLE void openDataDirectory();
    Q_INVOKABLE void setTaskbarWindow(QObject *window);
    Q_INVOKABLE void setTaskbarProgress(double progress, bool active);
    Q_INVOKABLE void notify(const QString &title, const QString &body,
                            const QString &urgency = QStringLiteral("normal"));
    Q_INVOKABLE void playAlarm();

signals:
    void notificationRequested(const QString &title, const QString &body,
                               const QString &urgency);

private:
    QPointer<QWindow> m_taskbarWindow;
};

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
