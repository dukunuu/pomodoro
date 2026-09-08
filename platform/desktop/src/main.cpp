#include "PlatformBridge.h"

#include <QAction>
#include <QApplication>
#include <QDebug>
#include <QDir>
#include <QFont>
#include <QFontMetricsF>
#include <QIcon>
#include <QLockFile>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QPointer>
#include <QFile>
#include <QFontDatabase>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QSysInfo>
#include <QTextStream>
#include <QStandardPaths>
#include <QSystemTrayIcon>
#include <QTimer>
#include <QUrl>
#include <QWindow>

#include <memory>

namespace {

const char *kServiceObjectName = "pomodoroService";

// Draws the remaining time as a menu-bar image.
//
// Omarchy shows the countdown directly in the bar. macOS status items hold an
// image rather than a live control, so render the text into one. The icon is
// marked as a mask so macOS recolors it for the light and dark menu bar
// instead of leaving black text on a dark background.
QIcon renderTextIcon(const QString &text)
{
    QFont font = QGuiApplication::font();
    font.setPixelSize(13);
    font.setWeight(QFont::Medium);

    const QFontMetricsF metrics(font);
    const qreal height = 22.0;
    const qreal width = std::max(qreal(24.0), metrics.horizontalAdvance(text) + 6.0);
    const qreal scale = 2.0; // Render for Retina; macOS downsamples for 1x.

    QPixmap pixmap(qRound(width * scale), qRound(height * scale));
    pixmap.setDevicePixelRatio(scale);
    pixmap.fill(Qt::transparent);
    {
        QPainter painter(&pixmap);
        painter.setRenderHint(QPainter::TextAntialiasing);
        painter.setFont(font);
        painter.setPen(Qt::black);
        painter.drawText(QRectF(0, 0, width, height), Qt::AlignCenter, text);
    }

    QIcon icon(pixmap);
    icon.setIsMask(true);
    return icon;
}

// Mirrors the live service state onto the tray item.
//
// The service is a QML object, so rather than binding to generated change
// signals by name this samples it once a second. The timer only ever ticks in
// whole seconds, and the update is skipped when nothing changed.
class TrayPresenter : public QObject
{
public:
    TrayPresenter(QSystemTrayIcon *tray, QObject *service, const QIcon &fallback, QObject *parent = nullptr)
        : QObject(parent)
        , m_tray(tray)
        , m_service(service)
        , m_fallback(fallback)
    {
        auto *timer = new QTimer(this);
        timer->setInterval(1000);
        connect(timer, &QTimer::timeout, this, &TrayPresenter::refresh);
        timer->start();
        refresh();
    }

private:
    void refresh()
    {
        if (!m_service)
            return;

        const QString remaining = m_service->property("remainingText").toString();
        const QString phase = m_service->property("phaseLabel").toString();
        const QString status = m_service->property("statusLabel").toString();
        if (remaining == m_remaining && status == m_status)
            return;

        m_remaining = remaining;
        m_status = status;
        m_tray->setToolTip(QStringLiteral("Pomodoro — %1 · %2 · %3").arg(phase, remaining, status));
#ifdef Q_OS_MACOS
        const QString icon = m_service->property("phaseIcon").toString();
        m_tray->setIcon(renderTextIcon(icon.isEmpty() ? remaining : icon + QLatin1Char(' ') + remaining));
#else
        Q_UNUSED(m_fallback);
#endif
    }

    QSystemTrayIcon *m_tray = nullptr;
    QPointer<QObject> m_service;
    QIcon m_fallback;
    QString m_remaining;
    QString m_status;
};

// Reports which implementation actually backs each compatibility module, plus
// the paths the integration bridges will use.
//
// The desktop app registers QML modules named "Quickshell.Io", "qs.Commons",
// and "qs.Ui" so the Omarchy service and dashboard files run unmodified. On a
// developer's Linux box the real Quickshell may also be installed, and on any
// host a stale deployment can shadow a module, so make the resolved type
// visible rather than leaving it to be guessed.
int runDiagnostics(QQmlApplicationEngine &engine, PlatformBridge &platform)
{
    QTextStream out(stdout);
    out << "Pomodoro " << QCoreApplication::applicationVersion() << "\n";
    out << "  platform          " << QSysInfo::prettyProductName() << " ("
        << QSysInfo::currentCpuArchitecture() << ")\n";
    out << "  qt                " << qVersion() << "\n";
    out << "  state directory   " << platform.stateDirectory() << "\n";

    const auto reportCommand = [&out](const char *label, const QString &command) {
        out << "  " << label << QString(18 - int(qstrlen(label)), QLatin1Char(' '))
            << command << (QFile::exists(command) ? "" : "   [missing]") << "\n";
    };
    reportCommand("integrations", platform.integrationCommand());
    reportCommand("google auth", platform.googleAuthCommand());
    reportCommand("whistler setup", platform.whistlerSetupCommand());
    reportCommand("whistler import", platform.whistlerImportCommand());

    const auto probe = [&engine, &out](const QString &import, const QString &type) {
        QQmlComponent component(&engine);
        component.setData(QStringLiteral("import %1\n%2 {}").arg(import, type).toUtf8(), QUrl());
        std::unique_ptr<QObject> object(component.create());
        out << "  " << import << '.' << type
            << QString(int(std::max(qsizetype(1), 16 - import.size() - type.size())), QLatin1Char(' '))
            << (object ? QString::fromLatin1(object->metaObject()->className())
                       : QStringLiteral("UNRESOLVED: ") + component.errorString().trimmed())
            << "\n";
    };
    probe(QStringLiteral("Quickshell.Io"), QStringLiteral("FileView"));
    probe(QStringLiteral("Quickshell.Io"), QStringLiteral("Process"));
    probe(QStringLiteral("Quickshell.Io"), QStringLiteral("IpcHandler"));

    out << "  nerd font         "
        << (QFontDatabase::families().filter(QStringLiteral("Nerd Font")).isEmpty()
                ? "not installed (using fallback icons)"
                : "installed")
        << "\n";
    return 0;
}

} // namespace

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("Dukunuu"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("local.pomodoro"));
    QCoreApplication::setApplicationName(QStringLiteral("Pomodoro"));
    QCoreApplication::setApplicationVersion(QStringLiteral(POMODORO_VERSION));
    QApplication::setQuitOnLastWindowClosed(false);

    // One timer per user. A second copy would race on the same state file and
    // double every Calendar event.
    const QString dataDirectory = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(dataDirectory);
    QLockFile lock(QDir(dataDirectory).filePath(QStringLiteral("pomodoro.lock")));
    lock.setStaleLockTime(0);
    if (!lock.tryLock(100)) {
        qWarning("Pomodoro is already running.");
        return 0;
    }

    QQmlApplicationEngine engine;
    if (app.arguments().contains(QStringLiteral("--diagnose"))) {
        PlatformBridge probeBridge;
        return runDiagnostics(engine, probeBridge);
    }

    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app,
                     [](const QList<QQmlError> &warnings) {
                         for (const QQmlError &warning : warnings)
                             qWarning().noquote() << warning.toString();
                     });
    engine.loadFromModule("Pomodoro", "Main");

    if (engine.rootObjects().isEmpty())
        return 1;

    auto *window = qobject_cast<QWindow *>(engine.rootObjects().constFirst());
    if (!window)
        return 1;

    auto *platform = engine.singletonInstance<PlatformBridge *>(QStringLiteral("Pomodoro"),
                                                                QStringLiteral("Bridge"));
    if (!platform)
        return 1;
    platform->setTaskbarWindow(window);

    auto *service = window->findChild<QObject *>(QLatin1String(kServiceObjectName));
    auto *timerWidget = qobject_cast<QWindow *>(window->findChild<QObject *>(QStringLiteral("timerWidget")));

    const QIcon icon(QStringLiteral(":/qt/qml/Pomodoro/assets/pomodoro.svg"));
    window->setIcon(icon);

    QSystemTrayIcon tray(icon);
    tray.setToolTip(QStringLiteral("Pomodoro"));

    QMenu trayMenu;
    QAction openAction(QStringLiteral("Open dashboard"), &trayMenu);
    QAction showTimerWidgetAction(QStringLiteral("Show timer widget"), &trayMenu);
    QAction startPauseAction(QStringLiteral("Start / pause"), &trayMenu);
    QAction skipAction(QStringLiteral("Skip phase"), &trayMenu);
    QAction quitAction(QStringLiteral("Quit"), &trayMenu);
    trayMenu.addAction(&openAction);
    trayMenu.addAction(&showTimerWidgetAction);
    trayMenu.addSeparator();
    trayMenu.addAction(&startPauseAction);
    trayMenu.addAction(&skipAction);
    trayMenu.addSeparator();
    trayMenu.addAction(&quitAction);
    tray.setContextMenu(&trayMenu);

    const auto showWindow = [window]() {
        window->show();
        window->raise();
        window->requestActivate();
    };
    const auto showTimerWidget = [timerWidget]() {
        if (!timerWidget)
            return;
        timerWidget->show();
        timerWidget->raise();
        timerWidget->requestActivate();
    };

    QObject::connect(&openAction, &QAction::triggered, &app, showWindow);
    QObject::connect(&showTimerWidgetAction, &QAction::triggered, &app, showTimerWidget);
    showTimerWidgetAction.setEnabled(timerWidget != nullptr);

#ifndef Q_OS_MACOS
    // The macOS status item opens its menu on any click, so a left click must
    // not also raise the dashboard.
    QObject::connect(&tray, &QSystemTrayIcon::activated, &app,
                     [&showWindow](QSystemTrayIcon::ActivationReason reason) {
                         if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick)
                             showWindow();
                     });
#endif

    if (service) {
        QObject::connect(&startPauseAction, &QAction::triggered, &app, [service]() {
            QMetaObject::invokeMethod(service, "toggle", Qt::QueuedConnection);
        });
        QObject::connect(&skipAction, &QAction::triggered, &app, [service]() {
            QMetaObject::invokeMethod(service, "skip", Qt::QueuedConnection);
        });
        new TrayPresenter(&tray, service, icon, &app);
    }
    QObject::connect(&quitAction, &QAction::triggered, &app, &QCoreApplication::quit);
    QObject::connect(platform, &PlatformBridge::notificationRequested, &app,
                     [&tray](const QString &title, const QString &body, const QString &) {
                         tray.showMessage(title, body, QSystemTrayIcon::Information, 5000);
                     });

    tray.show();

#if defined(Q_OS_WIN)
    if (timerWidget)
        showTimerWidget();
    else
        showWindow();
#elif defined(Q_OS_MACOS)
    // The menu-bar countdown is the resting state, matching the Omarchy bar.
#else
    showWindow();
#endif
    return app.exec();
}
