#include "PlatformBridge.h"

#include <QApplication>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>

#include <algorithm>

PlatformBridge::PlatformBridge(QObject *parent)
    : QObject(parent)
{
}

QString PlatformBridge::homeDirectory() const
{
    return QDir::homePath();
}

QString PlatformBridge::stateDirectory() const
{
    return QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
}

QString PlatformBridge::env(const QString &name) const
{
    return QString::fromLocal8Bit(qgetenv(name.toLocal8Bit().constData()));
}

void PlatformBridge::execDetached(const QStringList &command)
{
    if (command.isEmpty() || command.first().isEmpty())
        return;

    QProcess::startDetached(command.first(), command.mid(1));
}

void PlatformBridge::notify(const QString &title, const QString &body, const QString &urgency)
{
    emit notificationRequested(title, body, urgency);
}

void PlatformBridge::playAlarm()
{
    QApplication::beep();
}

DesktopStream::DesktopStream(QObject *parent)
    : QObject(parent)
{
}

QString DesktopStream::text() const
{
    return m_text;
}

bool DesktopStream::waitForEnd() const
{
    return m_waitForEnd;
}

void DesktopStream::setWaitForEnd(bool value)
{
    m_waitForEnd = value;
}

void DesktopStream::setSplitLines(bool value)
{
    m_splitLines = value;
}

void DesktopStream::reset()
{
    m_pending.clear();
    if (!m_text.isEmpty()) {
        m_text.clear();
        emit textChanged();
    }
}

void DesktopStream::consume(const QByteArray &data)
{
    if (data.isEmpty())
        return;

    if (!m_splitLines) {
        m_text += QString::fromUtf8(data);
        emit textChanged();
        return;
    }

    m_pending += data;
    while (true) {
        const qsizetype newline = m_pending.indexOf('\n');
        if (newline < 0)
            break;

        QByteArray line = m_pending.left(newline);
        m_pending.remove(0, newline + 1);
        if (line.endsWith('\r'))
            line.chop(1);
        emit read(QString::fromUtf8(line));
    }
}

void DesktopStream::finish()
{
    if (m_splitLines && !m_pending.isEmpty()) {
        QByteArray line = m_pending;
        m_pending.clear();
        if (line.endsWith('\r'))
            line.chop(1);
        emit read(QString::fromUtf8(line));
    }
    emit streamFinished();
}

DesktopSplitParser::DesktopSplitParser(QObject *parent)
    : DesktopStream(parent)
{
    setSplitLines(true);
}

DesktopStdioCollector::DesktopStdioCollector(QObject *parent)
    : DesktopStream(parent)
{
    setSplitLines(false);
}

DesktopProcess::DesktopProcess(QObject *parent)
    : QObject(parent)
{
    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this]() {
        consumeOutput(m_stdoutDevice, m_process.readAllStandardOutput());
    });
    connect(&m_process, &QProcess::readyReadStandardError, this, [this]() {
        consumeOutput(m_stderrDevice, m_process.readAllStandardError());
    });
    connect(&m_process,
            &QProcess::finished,
            this,
            [this](int exitCode, QProcess::ExitStatus) { complete(exitCode); });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            complete(-1);
    });
}

QStringList DesktopProcess::command() const
{
    return m_command;
}

void DesktopProcess::setCommand(const QStringList &command)
{
    if (command == m_command)
        return;
    m_command = command;
    emit commandChanged();
}

bool DesktopProcess::running() const
{
    return m_running;
}

void DesktopProcess::setRunning(bool running)
{
    if (running == m_running)
        return;

    if (running) {
        m_running = true;
        emit runningChanged();
        startProcess();
        return;
    }

    if (m_process.state() != QProcess::NotRunning)
        m_process.kill();
    complete(-1);
}

QObject *DesktopProcess::stdoutDevice() const
{
    return m_stdoutDevice;
}

void DesktopProcess::setStdoutDevice(QObject *device)
{
    if (device == m_stdoutDevice)
        return;
    m_stdoutDevice = device;
    emit streamsChanged();
}

QObject *DesktopProcess::stderrDevice() const
{
    return m_stderrDevice;
}

void DesktopProcess::setStderrDevice(QObject *device)
{
    if (device == m_stderrDevice)
        return;
    m_stderrDevice = device;
    emit streamsChanged();
}

void DesktopProcess::startProcess()
{
    resetStreams();
    if (m_command.isEmpty() || m_command.first().isEmpty()) {
        complete(0);
        return;
    }

    // The Linux service uses mkdir -p to prepare its state directory. Keep the
    // QML service unchanged while handling that tiny platform seam natively.
    if (m_command.first() == QStringLiteral("mkdir")) {
        QString directory;
        for (const QString &argument : m_command) {
            if (!argument.startsWith(QLatin1Char('-')))
                directory = argument;
        }
        complete(!directory.isEmpty() && QDir().mkpath(directory) ? 0 : 1);
        return;
    }

    m_process.start(m_command.first(), m_command.mid(1));
}

void DesktopProcess::complete(int exitCode)
{
    if (!m_running)
        return;

    if (m_process.state() != QProcess::NotRunning)
        m_process.kill();
    consumeOutput(m_stdoutDevice, m_process.readAllStandardOutput());
    consumeOutput(m_stderrDevice, m_process.readAllStandardError());
    finishStream(m_stdoutDevice);
    finishStream(m_stderrDevice);
    m_running = false;
    emit runningChanged();
    emit exited(exitCode);
}

void DesktopProcess::resetStreams()
{
    if (auto *stream = qobject_cast<DesktopStream *>(m_stdoutDevice))
        stream->reset();
    if (auto *stream = qobject_cast<DesktopStream *>(m_stderrDevice))
        stream->reset();
}

void DesktopProcess::consumeOutput(QObject *device, const QByteArray &data)
{
    if (auto *stream = qobject_cast<DesktopStream *>(device))
        stream->consume(data);
}

void DesktopProcess::finishStream(QObject *device)
{
    if (auto *stream = qobject_cast<DesktopStream *>(device))
        stream->finish();
}

DesktopFileView::DesktopFileView(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &DesktopFileView::onWatchedFileChanged);
}

QString DesktopFileView::path() const
{
    return m_path;
}

void DesktopFileView::setPath(const QString &path)
{
    if (path == m_path)
        return;
    m_watcher.removePaths(m_watcher.files());
    m_path = path;
    emit pathChanged();
    updateWatcher();
}

bool DesktopFileView::watchChanges() const
{
    return m_watchChanges;
}

void DesktopFileView::setWatchChanges(bool value)
{
    if (value == m_watchChanges)
        return;
    m_watchChanges = value;
    updateWatcher();
}

bool DesktopFileView::atomicWrites() const
{
    return m_atomicWrites;
}

void DesktopFileView::setAtomicWrites(bool value)
{
    m_atomicWrites = value;
}

bool DesktopFileView::printErrors() const
{
    return m_printErrors;
}

void DesktopFileView::setPrintErrors(bool value)
{
    m_printErrors = value;
}

QString DesktopFileView::text() const
{
    return m_text;
}

void DesktopFileView::reload()
{
    if (m_path.isEmpty()) {
        emit loadFailed();
        return;
    }

    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (m_printErrors && file.exists())
            qWarning("Pomodoro: unable to read state file %s", qPrintable(m_path));
        updateWatcher();
        emit loadFailed();
        return;
    }

    m_text = QString::fromUtf8(file.readAll());
    updateWatcher();
    emit loaded();
}

void DesktopFileView::setText(const QString &value)
{
    if (m_path.isEmpty())
        return;

    const QFileInfo info(m_path);
    if (!QDir().mkpath(info.absolutePath())) {
        if (m_printErrors)
            qWarning("Pomodoro: unable to create state directory %s", qPrintable(info.absolutePath()));
        return;
    }

    bool written = false;
    if (m_atomicWrites) {
        QSaveFile file(m_path);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(value.toUtf8());
            written = file.commit();
        }
    } else {
        QFile file(m_path);
        if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            written = file.write(value.toUtf8()) == value.toUtf8().size();
            file.close();
        }
    }

    if (!written && m_printErrors)
        qWarning("Pomodoro: unable to write state file %s", qPrintable(m_path));
    m_text = value;
    updateWatcher();
}

void DesktopFileView::updateWatcher()
{
    m_watcher.removePaths(m_watcher.files());
    if (m_watchChanges && !m_path.isEmpty() && QFile::exists(m_path))
        m_watcher.addPath(m_path);
}

void DesktopFileView::onWatchedFileChanged(const QString &path)
{
    if (path != m_path)
        return;
    emit fileChanged();
    updateWatcher();
}
