#include "RPCS3CoreBridge.h"

#include <QApplication>
#include <QDir>
#include <QFileInfo>
#include <QListWidget>
#include <QMainWindow>
#include <QMessageBox>
#include <QPointer>
#include <QStatusBar>
#include <QTimer>
#include <QWidget>

namespace
{
QString locateBootExecutable(const QString& path)
{
    const QFileInfo info(path);
    if (info.isFile())
        return info.absoluteFilePath();
    if (!info.isDir())
        return {};

    const QStringList candidates = {
        QDir(path).filePath(QStringLiteral("EBOOT.BIN")),
        QDir(path).filePath(QStringLiteral("USRDIR/EBOOT.BIN")),
        QDir(path).filePath(QStringLiteral("PS3_GAME/USRDIR/EBOOT.BIN")),
        QDir(path).filePath(QStringLiteral("vsh/module/vsh.self")),
    };
    for (const QString& candidate : candidates)
    {
        if (QFileInfo(candidate).isFile())
            return candidate;
    }
    return {};
}

void setSurfaceVisible(QListWidget* list, QWidget* renderHost, bool visible)
{
    if (list)
        list->setVisible(!visible);
    if (renderHost)
        renderHost->setVisible(visible);
}

void installLaunchGuard()
{
    for (QWidget* topLevel : QApplication::topLevelWidgets())
    {
        if (!topLevel)
            continue;

        auto* list = topLevel->findChild<QListWidget*>(QStringLiteral("rpcs3GameList"));
        auto* renderHost = topLevel->findChild<QWidget*>(QStringLiteral("rpcs3IOSNativeRenderHost"));
        if (!list || !renderHost || list->property("rpcs3IOSLaunchGuardInstalled").toBool())
            continue;

        list->setProperty("rpcs3IOSLaunchGuardInstalled", true);
        QObject::disconnect(list, nullptr, topLevel, nullptr);

        QPointer<QWidget> guardedWindow(topLevel);
        QPointer<QListWidget> guardedList(list);
        QPointer<QWidget> guardedRenderHost(renderHost);
        QObject::connect(list, &QListWidget::itemActivated, topLevel,
            [guardedWindow, guardedList, guardedRenderHost](QListWidgetItem* item)
            {
                if (!guardedWindow || !guardedList || !guardedRenderHost || !item)
                    return;

                const QString representedPath = item->data(Qt::UserRole).toString();
                const QString bootPath = locateBootExecutable(representedPath);
                if (bootPath.isEmpty())
                {
                    QMessageBox::warning(guardedWindow, item->text(),
                        QObject::tr("No EBOOT.BIN, SELF, or ELF executable was found for this entry."));
                    return;
                }

                setSurfaceVisible(guardedList, guardedRenderHost, true);
                QApplication::processEvents();
                const WId nativeId = guardedRenderHost->winId();
                if (!nativeId || !rpcs3_ios_core_set_render_view(reinterpret_cast<void*>(nativeId)))
                {
                    setSurfaceVisible(guardedList, guardedRenderHost, false);
                    const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
                    QMessageBox::critical(guardedWindow, QObject::tr("Renderer Surface Missing"),
                        diagnostics.message ? QString::fromUtf8(diagnostics.message)
                                            : QObject::tr("RPCS3 could not attach its iOS render surface."));
                    return;
                }

                if (auto* mainWindow = qobject_cast<QMainWindow*>(guardedWindow.data()))
                    mainWindow->statusBar()->showMessage(QObject::tr("Booting %1 through upstream Emulator::BootGame…").arg(item->text()));

                if (!rpcs3_ios_core_boot_elf(bootPath.toUtf8().constData()))
                {
                    setSurfaceVisible(guardedList, guardedRenderHost, false);
                    const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
                    QMessageBox::critical(guardedWindow, QObject::tr("Installed Title Boot Failed"),
                        QObject::tr("Installed path: %1\n\n%2")
                            .arg(bootPath,
                                 diagnostics.message ? QString::fromUtf8(diagnostics.message)
                                                     : QObject::tr("RPCS3 returned no boot diagnostic.")));
                    return;
                }

                if (auto* mainWindow = qobject_cast<QMainWindow*>(guardedWindow.data()))
                    mainWindow->statusBar()->showMessage(QObject::tr("Title started through RPCS3 Vulkan over MoltenVK"), 6000);
            });
    }
}

void scheduleLaunchGuard()
{
    QTimer::singleShot(0, qApp, []()
    {
        installLaunchGuard();
        QTimer::singleShot(250, qApp, installLaunchGuard);
    });
}
} // namespace

Q_COREAPP_STARTUP_FUNCTION(scheduleLaunchGuard)
