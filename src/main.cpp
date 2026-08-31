#include "PlatformBridge.h"

#include <QAction>
#include <QApplication>
#include <QIcon>
#include <QDebug>
#include <QMenu>
#include <QQmlApplicationEngine>
#include <QUrl>
#include <QQmlContext>
#include <QSystemTrayIcon>
#include <QWindow>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("Dukunuu"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("local.pomodoro"));
    QCoreApplication::setApplicationName(QStringLiteral("Pomodoro"));
    QApplication::setQuitOnLastWindowClosed(false);

    PlatformBridge platform;
    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app,
                     [](const QList<QQmlError> &warnings) {
                         for (const QQmlError &warning : warnings)
                             qWarning().noquote() << warning.toString();
                     });
    engine.rootContext()->setContextProperty(QStringLiteral("platform"), &platform);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/PomodoroWindows/qml/Main.qml")));

    if (engine.rootObjects().isEmpty())
        return 1;

    auto *window = qobject_cast<QWindow *>(engine.rootObjects().constFirst());
    if (!window)
        return 1;

    auto *service = window->findChild<QObject *>(QStringLiteral("pomodoroService"));
    const QIcon icon(QStringLiteral(":/qt/qml/PomodoroWindows/assets/pomodoro.svg"));
    window->setIcon(icon);
    QSystemTrayIcon tray(icon);
    tray.setToolTip(QStringLiteral("Pomodoro"));

    QMenu trayMenu;
    QAction openAction(QStringLiteral("Open dashboard"), &trayMenu);
    QAction startPauseAction(QStringLiteral("Start / pause"), &trayMenu);
    QAction skipAction(QStringLiteral("Skip phase"), &trayMenu);
    trayMenu.addAction(&openAction);
    trayMenu.addAction(&startPauseAction);
    trayMenu.addAction(&skipAction);
    trayMenu.addSeparator();
    QAction quitAction(QStringLiteral("Quit"), &trayMenu);
    trayMenu.addAction(&quitAction);
    tray.setContextMenu(&trayMenu);

    const auto showWindow = [window]() {
        window->show();
        window->raise();
        window->requestActivate();
    };

    QObject::connect(&openAction, &QAction::triggered, &app, showWindow);
    QObject::connect(&tray, &QSystemTrayIcon::activated, &app,
                     [&showWindow](QSystemTrayIcon::ActivationReason reason) {
                         if (reason == QSystemTrayIcon::Trigger ||
                             reason == QSystemTrayIcon::DoubleClick) {
                             showWindow();
                         }
                     });
    if (service) {
        QObject::connect(&startPauseAction, &QAction::triggered, &app, [service]() {
            QMetaObject::invokeMethod(service, "toggle", Qt::QueuedConnection);
        });
        QObject::connect(&skipAction, &QAction::triggered, &app, [service]() {
            QMetaObject::invokeMethod(service, "skip", Qt::QueuedConnection);
        });
    }
    QObject::connect(&quitAction, &QAction::triggered, &app, &QCoreApplication::quit);
    QObject::connect(&platform, &PlatformBridge::notificationRequested, &app,
                     [&tray](const QString &title, const QString &body, const QString &) {
                         tray.showMessage(title, body, QSystemTrayIcon::Information, 5000);
                     });

    tray.show();
    showWindow();
    return app.exec();
}
