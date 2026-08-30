#include "PomodoroService.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>

#include <algorithm>
#include <cmath>

PomodoroService::PomodoroService(QObject *parent)
    : QObject(parent)
{
    m_timer.setInterval(250);
    connect(&m_timer, &QTimer::timeout, this, &PomodoroService::tick);
    loadState();
}

QString PomodoroService::phase() const
{
    return m_phase;
}

QString PomodoroService::phaseLabel() const
{
    if (m_phase == QStringLiteral("long"))
        return QStringLiteral("Long break");
    if (m_phase == QStringLiteral("short"))
        return QStringLiteral("Short break");
    return QStringLiteral("Focus");
}

QString PomodoroService::nextPhaseLabel() const
{
    if (m_phase != QStringLiteral("focus"))
        return QStringLiteral("Focus");
    return nextPhaseForCompletion() == QStringLiteral("long")
               ? QStringLiteral("Long break")
               : QStringLiteral("Short break");
}

QString PomodoroService::remainingText() const
{
    const int absoluteSeconds = std::abs(m_remainingSeconds);
    const int minutes = absoluteSeconds / 60;
    const int seconds = absoluteSeconds % 60;
    const QString value = QStringLiteral("%1:%2")
                              .arg(minutes, 2, 10, QLatin1Char('0'))
                              .arg(seconds, 2, 10, QLatin1Char('0'));
    return m_remainingSeconds < 0 ? QStringLiteral("+") + value : value;
}

QString PomodoroService::statusLabel() const
{
    if (m_running)
        return overtime() ? QStringLiteral("Overtime") : QStringLiteral("Running");
    return m_remainingSeconds == durationForPhase(m_phase) ? QStringLiteral("Ready")
                                                            : QStringLiteral("Paused");
}

bool PomodoroService::running() const
{
    return m_running;
}

bool PomodoroService::overtime() const
{
    return m_remainingSeconds < 0;
}

bool PomodoroService::hasActivePhase() const
{
    return m_running || m_phaseRang || m_remainingSeconds != durationForPhase(m_phase);
}

int PomodoroService::remainingSeconds() const
{
    return m_remainingSeconds;
}

int PomodoroService::completedFocus() const
{
    return m_completedFocus;
}

QString PomodoroService::activeNote() const
{
    return m_activeNote;
}

void PomodoroService::setActiveNote(const QString &note)
{
    QString normalized = note.simplified();
    if (normalized.size() > 240)
        normalized.truncate(240);
    if (normalized == m_activeNote)
        return;

    m_activeNote = normalized;
    emit activeNoteChanged();
    saveState();
}

void PomodoroService::start()
{
    if (m_running)
        return;

    if (m_remainingSeconds == 0)
        m_remainingSeconds = durationForPhase(m_phase);

    m_endAtMs = nowMs() + static_cast<qint64>(m_remainingSeconds) * 1000;
    m_running = true;
    m_timer.start();
    saveState();
    notifyState();
}

void PomodoroService::pause()
{
    if (!m_running)
        return;

    updateFromClock();
    m_running = false;
    m_endAtMs = 0;
    m_timer.stop();
    saveState();
    notifyState();
}

void PomodoroService::toggle()
{
    if (m_running)
        pause();
    else
        start();
}

void PomodoroService::skip()
{
    if (m_running)
        updateFromClock();

    m_running = false;
    m_endAtMs = 0;
    m_timer.stop();
    m_phaseRang = false;
    transitionTo(m_phase == QStringLiteral("focus") ? QStringLiteral("short")
                                                      : QStringLiteral("focus"));
    saveState();
    notifyState();
}

void PomodoroService::finishPhase()
{
    if (!hasActivePhase())
        return;

    if (m_running)
        updateFromClock();

    m_running = false;
    m_endAtMs = 0;
    m_timer.stop();
    if (m_phase == QStringLiteral("focus"))
        ++m_completedFocus;

    const QString next = m_phase == QStringLiteral("focus") ? nextPhaseForCompletion()
                                                               : QStringLiteral("focus");
    transitionTo(next);
    saveState();
    notifyState();
}

void PomodoroService::reset()
{
    m_running = false;
    m_endAtMs = 0;
    m_timer.stop();
    m_phaseRang = false;
    m_remainingSeconds = durationForPhase(m_phase);
    m_activeNote.clear();
    emit activeNoteChanged();
    saveState();
    notifyState();
}

void PomodoroService::resetAll()
{
    m_running = false;
    m_endAtMs = 0;
    m_timer.stop();
    m_phase = QStringLiteral("focus");
    m_phaseRang = false;
    m_remainingSeconds = durationForPhase(m_phase);
    m_completedFocus = 0;
    m_activeNote.clear();
    emit activeNoteChanged();
    saveState();
    notifyState();
}

qint64 PomodoroService::nowMs() const
{
    return QDateTime::currentMSecsSinceEpoch();
}

int PomodoroService::durationForPhase(const QString &phaseName) const
{
    if (phaseName == QStringLiteral("long"))
        return kLongBreakMinutes * 60;
    if (phaseName == QStringLiteral("short"))
        return kShortBreakMinutes * 60;
    return kFocusMinutes * 60;
}

QString PomodoroService::nextPhaseForCompletion() const
{
    return (m_completedFocus + 1) % kLongBreakEvery == 0 ? QStringLiteral("long")
                                                          : QStringLiteral("short");
}

QString PomodoroService::stateFilePath() const
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    return QDir(base).filePath(QStringLiteral("pomodoro.json"));
}

void PomodoroService::loadState()
{
    QFile file(stateFilePath());
    if (!file.open(QIODevice::ReadOnly)) {
        notifyState();
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject()) {
        notifyState();
        return;
    }

    const QJsonObject object = document.object();
    const QString savedPhase = object.value(QStringLiteral("phase")).toString();
    if (savedPhase == QStringLiteral("focus") || savedPhase == QStringLiteral("short") ||
        savedPhase == QStringLiteral("long")) {
        m_phase = savedPhase;
    }

    const int fallback = durationForPhase(m_phase);
    m_remainingSeconds = object.value(QStringLiteral("remainingSeconds")).toInt(fallback);
    m_completedFocus = std::max(0, object.value(QStringLiteral("completedFocus")).toInt(0));
    m_activeNote = object.value(QStringLiteral("activeNote")).toString().simplified();
    if (m_activeNote.size() > 240)
        m_activeNote.truncate(240);
    m_phaseRang = object.value(QStringLiteral("phaseRang")).toBool(false);
    m_endAtMs = static_cast<qint64>(object.value(QStringLiteral("endAt")).toDouble(0));
    m_running = object.value(QStringLiteral("running")).toBool(false) && m_endAtMs > 0;

    if (m_running) {
        updateFromClock();
        m_timer.start();
    } else {
        m_endAtMs = 0;
    }
    notifyState();
}

void PomodoroService::saveState() const
{
    const QString path = stateFilePath();
    const QFileInfo info(path);
    QDir().mkpath(info.absolutePath());

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return;

    QJsonObject object;
    object.insert(QStringLiteral("version"), 1);
    object.insert(QStringLiteral("phase"), m_phase);
    object.insert(QStringLiteral("running"), m_running);
    object.insert(QStringLiteral("endAt"), m_running ? static_cast<double>(m_endAtMs) : 0.0);
    object.insert(QStringLiteral("remainingSeconds"), m_remainingSeconds);
    object.insert(QStringLiteral("completedFocus"), m_completedFocus);
    object.insert(QStringLiteral("activeNote"), m_activeNote);
    object.insert(QStringLiteral("phaseRang"), m_phaseRang);
    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    file.write("\n");
    file.commit();
}

void PomodoroService::updateFromClock()
{
    if (!m_running || m_endAtMs <= 0)
        return;

    const qint64 difference = m_endAtMs - nowMs();
    const int seconds = static_cast<int>(std::ceil(static_cast<double>(difference) / 1000.0));
    if (seconds == m_remainingSeconds)
        return;

    m_remainingSeconds = seconds;
    if (seconds <= 0 && !m_phaseRang) {
        m_phaseRang = true;
        emit phaseReached(phaseLabel(), nextPhaseLabel());
    }
    notifyState();
}

void PomodoroService::transitionTo(const QString &nextPhase)
{
    m_phase = nextPhase;
    m_remainingSeconds = durationForPhase(m_phase);
    m_phaseRang = false;
    if (m_phase != QStringLiteral("focus"))
        m_activeNote.clear();
    emit activeNoteChanged();
}

void PomodoroService::notifyState()
{
    emit stateChanged();
}

void PomodoroService::tick()
{
    updateFromClock();
}
