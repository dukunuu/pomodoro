#pragma once

#include <QObject>
#include <QTimer>

class PomodoroService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString phase READ phase NOTIFY stateChanged)
    Q_PROPERTY(QString phaseLabel READ phaseLabel NOTIFY stateChanged)
    Q_PROPERTY(QString nextPhaseLabel READ nextPhaseLabel NOTIFY stateChanged)
    Q_PROPERTY(QString remainingText READ remainingText NOTIFY stateChanged)
    Q_PROPERTY(QString statusLabel READ statusLabel NOTIFY stateChanged)
    Q_PROPERTY(bool running READ running NOTIFY stateChanged)
    Q_PROPERTY(bool overtime READ overtime NOTIFY stateChanged)
    Q_PROPERTY(bool hasActivePhase READ hasActivePhase NOTIFY stateChanged)
    Q_PROPERTY(int remainingSeconds READ remainingSeconds NOTIFY stateChanged)
    Q_PROPERTY(int completedFocus READ completedFocus NOTIFY stateChanged)
    Q_PROPERTY(QString activeNote READ activeNote WRITE setActiveNote NOTIFY activeNoteChanged)

public:
    explicit PomodoroService(QObject *parent = nullptr);

    QString phase() const;
    QString phaseLabel() const;
    QString nextPhaseLabel() const;
    QString remainingText() const;
    QString statusLabel() const;
    bool running() const;
    bool overtime() const;
    bool hasActivePhase() const;
    int remainingSeconds() const;
    int completedFocus() const;
    QString activeNote() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void toggle();
    Q_INVOKABLE void skip();
    Q_INVOKABLE void finishPhase();
    Q_INVOKABLE void reset();
    Q_INVOKABLE void resetAll();
    Q_INVOKABLE void setActiveNote(const QString &note);

signals:
    void stateChanged();
    void activeNoteChanged();
    void phaseReached(const QString &phase, const QString &nextPhase);

private slots:
    void tick();

private:
    static constexpr int kFocusMinutes = 25;
    static constexpr int kShortBreakMinutes = 5;
    static constexpr int kLongBreakMinutes = 15;
    static constexpr int kLongBreakEvery = 4;

    qint64 nowMs() const;
    int durationForPhase(const QString &phaseName) const;
    QString nextPhaseForCompletion() const;
    QString stateFilePath() const;
    void loadState();
    void saveState() const;
    void updateFromClock();
    void transitionTo(const QString &nextPhase);
    void notifyState();

    QTimer m_timer;
    QString m_phase = QStringLiteral("focus");
    bool m_running = false;
    bool m_phaseRang = false;
    qint64 m_endAtMs = 0;
    int m_remainingSeconds = kFocusMinutes * 60;
    int m_completedFocus = 0;
    QString m_activeNote;
};
