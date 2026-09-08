#pragma once

// Per-OS behavior for the desktop hosts (Windows, macOS, and plain Linux
// desktops without Omarchy).
//
// The shared QML never calls into this class directly. It goes through
// platform/desktop/qml/Platform.qml, whose Omarchy counterpart is
// platform/quickshell/Platform.qml. Adding a member here means adding it to
// both Platform.qml files.

#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>

#include <QtQml/qqmlregistration.h>

class QWindow;

class PlatformBridge final : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Bridge)
    QML_SINGLETON

    Q_PROPERTY(QString stateDirectory READ stateDirectory CONSTANT)
    Q_PROPERTY(QString integrationCommand READ integrationCommand CONSTANT)
    Q_PROPERTY(QString whistlerImportCommand READ whistlerImportCommand CONSTANT)
    Q_PROPERTY(QString googleAuthCommand READ googleAuthCommand CONSTANT)
    Q_PROPERTY(QString whistlerSetupCommand READ whistlerSetupCommand CONSTANT)

public:
    explicit PlatformBridge(QObject *parent = nullptr);

    QString stateDirectory() const;
    QString integrationCommand() const;
    QString whistlerImportCommand() const;
    QString googleAuthCommand() const;
    QString whistlerSetupCommand() const;

    Q_INVOKABLE QString env(const QString &name) const;
    Q_INVOKABLE void execDetached(const QStringList &command);
    // Runs an interactive command in a visible console. Google OAuth and the
    // Whistler setup prompt for input, so they must not be detached silently.
    Q_INVOKABLE bool openCommandWindow(const QStringList &command);
    Q_INVOKABLE bool openPath(const QString &path);
    Q_INVOKABLE void notify(const QString &title, const QString &body,
                            const QString &urgency = QStringLiteral("normal"));
    Q_INVOKABLE void playAlarm();

    // Windows taskbar progress. A no-op on macOS, where the app is a menu-bar
    // agent with no Dock tile, and on Linux.
    void setTaskbarWindow(QWindow *window);
    Q_INVOKABLE void setTaskbarProgress(double progress, bool active);

signals:
    // Raised on the platforms whose notifications are delivered through the
    // tray icon. macOS posts through the notification center directly and does
    // not emit this.
    void notificationRequested(const QString &title, const QString &body,
                               const QString &urgency);

private:
    QPointer<QWindow> m_taskbarWindow;
    double m_lastAlarmMs = 0;
};
