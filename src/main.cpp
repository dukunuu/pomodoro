#include "PomodoroService.h"

#include <QAction>
#include <QApplication>
#include <QIcon>
#include <QMenu>
#include <QQmlApplicationEngine>
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

    PomodoroService service;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("pomodoroService"), &service);
    engine.loadFromModule(QStringLiteral("PomodoroWindows"), QStringLiteral("Main"));

    if (engine.rootObjects().isEmpty())
        return 1;

    auto *window = qobject_cast<QWindow *>(engine.rootObjects().constFirst());
    if (!window)
        return 1;

    const QIcon icon(QStringLiteral(":/qt/qml/PomodoroWindows/assets/pomodoro.svg"));
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
    QObject::connect(&startPauseAction, &QAction::triggered, &service,
                     &PomodoroService::toggle);
    QObject::connect(&skipAction, &QAction::triggered, &service,
                     &PomodoroService::skip);
    QObject::connect(&quitAction, &QAction::triggered, &app, &QCoreApplication::quit);

    QObject::connect(&service, &PomodoroService::stateChanged, &app, [&tray, &service]() {
        tray.setToolTip(QStringLiteral("Pomodoro — %1 %2")
                            .arg(service.phaseLabel(), service.remainingText()));
    });
    QObject::connect(&service, &PomodoroService::phaseReached, &app,
                     [&tray](const QString &phase, const QString &nextPhase) {
                         tray.showMessage(
                             QStringLiteral("Pomodoro %1 reached").arg(phase),
                             QStringLiteral("Continue working or move to %1.").arg(nextPhase),
                             QSystemTrayIcon::Information,
                             5000);
                     });

    tray.show();
    showWindow();
    return app.exec();
}
