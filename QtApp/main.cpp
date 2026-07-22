#include "RPCS3QtMainWindow.h"
#include "RPCS3CoreBridge.h"

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QCursor>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QLayout>
#include <QListWidget>
#include <QMessageBox>
#include <QPalette>
#include <QStandardPaths>
#include <QStatusBar>
#include <QTimer>
#include <QWidget>

#ifndef RPCS3_QT_BUILD_MARKER
#define RPCS3_QT_BUILD_MARKER "RPCS3 Qt iOS upstream main_window.ui"
#endif

namespace
{
QString uniqueStagingDestination(const QString& directory, const QString& fileName,
                                 const QString& fallbackBase, const QString& fallbackSuffix)
{
    QDir destination(directory);
    const QFileInfo source(fileName);
    const QString base = source.completeBaseName().isEmpty() ? fallbackBase : source.completeBaseName();
    const QString suffix = source.suffix().isEmpty()
        ? fallbackSuffix
        : QStringLiteral(".") + source.suffix();

    QString candidate = destination.filePath(base + suffix);
    if (!QFileInfo::exists(candidate))
        return candidate;

    for (int index = 1; index < 10000; ++index)
    {
        candidate = destination.filePath(QStringLiteral("%1-%2%3").arg(base).arg(index).arg(suffix));
        if (!QFileInfo::exists(candidate))
            return candidate;
    }

    return destination.filePath(QStringLiteral("%1-%2%3")
        .arg(base)
        .arg(QDateTime::currentMSecsSinceEpoch())
        .arg(suffix));
}

QString diagnosticsMessage()
{
    const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    return diagnostics.message
        ? QString::fromUtf8(diagnostics.message)
        : QObject::tr("RPCS3 returned no diagnostic message.");
}

QWidget* createNativeRenderHost(RPCS3QtMainWindow& window)
{
    QWidget* central = window.centralWidget();
    if (!central || !central->layout())
        return nullptr;

    auto* renderHost = new QWidget(central);
    renderHost->setObjectName(QStringLiteral("rpcs3IOSNativeRenderHost"));
    renderHost->setAttribute(Qt::WA_NativeWindow, true);
    renderHost->setAutoFillBackground(true);
    QPalette palette = renderHost->palette();
    palette.setColor(QPalette::Window, Qt::black);
    renderHost->setPalette(palette);
    renderHost->setMinimumSize(1, 1);
    renderHost->hide();
    central->layout()->addWidget(renderHost);
    return renderHost;
}

void setGameSurfaceVisible(RPCS3QtMainWindow& window, QWidget* renderHost, bool visible)
{
    if (QListWidget* gameList = window.findChild<QListWidget*>(QStringLiteral("rpcs3GameList")))
        gameList->setVisible(!visible);
    if (renderHost)
        renderHost->setVisible(visible);
}

bool attachVisibleRenderSurface(RPCS3QtMainWindow& window, QWidget* renderHost)
{
    if (!renderHost)
        return false;

    setGameSurfaceVisible(window, renderHost, true);
    QApplication::processEvents();
    const WId nativeId = renderHost->winId();
    if (!nativeId || !rpcs3_ios_core_set_render_view(reinterpret_cast<void*>(nativeId)))
    {
        setGameSurfaceVisible(window, renderHost, false);
        return false;
    }
    return true;
}

void updateFirmwareDependentActions(RPCS3QtMainWindow& window)
{
    const bool ready = rpcs3_ios_core_firmware_ready() != 0;
    if (QAction* packageAction = window.findChild<QAction*>(QStringLiteral("bootInstallPkgAct")))
    {
        packageAction->setEnabled(ready);
        packageAction->setToolTip(ready
            ? QObject::tr("Install a PS3 PKG through RPCS3")
            : QObject::tr("Install official PS3 firmware first"));
    }
    if (QAction* vshAction = window.findChild<QAction*>(QStringLiteral("bootVSHAct")))
        vshAction->setEnabled(ready);
}

void bindFirmwareFlow(RPCS3QtMainWindow& window)
{
    QAction* firmwareAction = window.findChild<QAction*>(QStringLiteral("bootInstallPupAct"));
    if (!firmwareAction)
        return;

    QObject::disconnect(firmwareAction, nullptr, &window, nullptr);
    QObject::connect(firmwareAction, &QAction::triggered, &window, [&window]()
    {
        if (rpcs3_ios_core_firmware_ready())
        {
            const char* currentVersionRaw = rpcs3_ios_core_firmware_version();
            const QString currentVersion = currentVersionRaw ? QString::fromUtf8(currentVersionRaw) : QString();
            const QString prompt = currentVersion.isEmpty()
                ? QObject::tr("PS3 firmware is already installed. Replace the current dev_flash installation?")
                : QObject::tr("PS3 firmware %1 is already installed. Replace the current dev_flash installation?")
                      .arg(currentVersion);
            if (QMessageBox::question(&window, QObject::tr("Reinstall PS3 Firmware"), prompt,
                                      QMessageBox::Yes | QMessageBox::No, QMessageBox::No) != QMessageBox::Yes)
                return;
        }

        const QString selected = QFileDialog::getOpenFileName(
            &window,
            QObject::tr("Install Official PS3 Firmware"),
            QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
            QObject::tr("PS3 update file (PS3UPDAT.PUP *.pup *.PUP);;All files (*)"));
        if (selected.isEmpty())
            return;

        const RPCS3IOSCoreDiagnostics before = rpcs3_ios_core_diagnostics();
        const QString dataRoot = before.data_path ? QString::fromUtf8(before.data_path) : QString();
        if (dataRoot.isEmpty())
        {
            QMessageBox::critical(&window, QObject::tr("Firmware Installation Failed"),
                                  QObject::tr("The RPCS3 sandbox data root is unavailable."));
            return;
        }

        const QString firmwareDirectory = QDir(dataRoot).filePath(QStringLiteral("firmware"));
        if (!QDir().mkpath(firmwareDirectory))
        {
            QMessageBox::critical(&window, QObject::tr("Firmware Installation Failed"),
                                  QObject::tr("Unable to create the firmware staging directory."));
            return;
        }

        const QString stagedPath = uniqueStagingDestination(
            firmwareDirectory, QFileInfo(selected).fileName(), QStringLiteral("PS3UPDAT"), QStringLiteral(".PUP"));
        if (!QFile::copy(selected, stagedPath))
        {
            QMessageBox::critical(&window, QObject::tr("Firmware Installation Failed"),
                                  QObject::tr("Unable to copy PS3UPDAT.PUP into the RPCS3 sandbox."));
            return;
        }

        window.statusBar()->showMessage(
            QObject::tr("Validating PUP hashes, decrypting SCE packages, and installing dev_flash…"));
        QApplication::setOverrideCursor(QCursor(Qt::WaitCursor));
        QApplication::processEvents();
        const int installed = rpcs3_ios_core_install_firmware(stagedPath.toUtf8().constData());
        QApplication::restoreOverrideCursor();

        if (!installed)
        {
            updateFirmwareDependentActions(window);
            QMessageBox::critical(&window, QObject::tr("Firmware Installation Failed"), diagnosticsMessage());
            return;
        }

        updateFirmwareDependentActions(window);
        const char* versionRaw = rpcs3_ios_core_firmware_version();
        const QString version = versionRaw ? QString::fromUtf8(versionRaw) : QString();
        window.statusBar()->showMessage(
            version.isEmpty()
                ? QObject::tr("PS3 firmware installed and dev_flash validated")
                : QObject::tr("PS3 firmware %1 installed and dev_flash validated").arg(version),
            7000);
        QMessageBox::information(
            &window,
            QObject::tr("PS3 Firmware Installed"),
            version.isEmpty()
                ? QObject::tr("RPCS3 installed the official firmware and validated dev_flash/vsh/module/vsh.self. PKG installation is now enabled.")
                : QObject::tr("RPCS3 installed firmware %1 and validated dev_flash/vsh/module/vsh.self. PKG installation is now enabled.")
                      .arg(version));
    });

    updateFirmwareDependentActions(window);
}

void bindPlayablePackageFlow(RPCS3QtMainWindow& window, QWidget* renderHost)
{
    QAction* installAction = window.findChild<QAction*>(QStringLiteral("bootInstallPkgAct"));
    if (!installAction)
        return;

    QObject::disconnect(installAction, nullptr, &window, nullptr);
    QObject::connect(installAction, &QAction::triggered, &window, [&window, renderHost]()
    {
        if (!rpcs3_ios_core_firmware_ready())
        {
            QMessageBox::warning(
                &window,
                QObject::tr("PS3 Firmware Required"),
                QObject::tr("Install an official PS3UPDAT.PUP before installing or booting a PKG."));
            if (QAction* firmwareAction = window.findChild<QAction*>(QStringLiteral("bootInstallPupAct")))
                firmwareAction->trigger();
            return;
        }

        const QString selected = QFileDialog::getOpenFileName(
            &window,
            QObject::tr("Install PS3 Package"),
            QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
            QObject::tr("PlayStation 3 packages (*.pkg *.PKG);;All files (*)"));
        if (selected.isEmpty())
            return;

        const RPCS3IOSCoreDiagnostics before = rpcs3_ios_core_diagnostics();
        const QString dataRoot = before.data_path ? QString::fromUtf8(before.data_path) : QString();
        if (dataRoot.isEmpty())
        {
            QMessageBox::critical(&window, QObject::tr("PKG Installation Failed"),
                                  QObject::tr("The RPCS3 sandbox data root is unavailable."));
            return;
        }

        const QString packageDirectory = QDir(dataRoot).filePath(QStringLiteral("packages"));
        if (!QDir().mkpath(packageDirectory))
        {
            QMessageBox::critical(&window, QObject::tr("PKG Installation Failed"),
                                  QObject::tr("Unable to create the package staging directory."));
            return;
        }

        const QString stagedPath = uniqueStagingDestination(
            packageDirectory, QFileInfo(selected).fileName(), QStringLiteral("package"), QStringLiteral(".pkg"));
        if (!QFile::copy(selected, stagedPath))
        {
            QMessageBox::critical(&window, QObject::tr("PKG Installation Failed"),
                                  QObject::tr("Unable to copy the selected package into the RPCS3 sandbox."));
            return;
        }

        window.statusBar()->showMessage(QObject::tr("Installing %1 through RPCS3 package_reader…")
                                         .arg(QFileInfo(selected).fileName()));
        QApplication::setOverrideCursor(QCursor(Qt::WaitCursor));
        const int installed = rpcs3_ios_core_install_pkg(stagedPath.toUtf8().constData());
        QApplication::restoreOverrideCursor();

        const RPCS3IOSCoreDiagnostics installDiagnostics = rpcs3_ios_core_diagnostics();
        if (!installed)
        {
            QMessageBox::critical(
                &window,
                QObject::tr("PKG Installation Failed"),
                installDiagnostics.message
                    ? QString::fromUtf8(installDiagnostics.message)
                    : QObject::tr("RPCS3 returned no package-install diagnostic."));
            return;
        }

        const char* installedBootPathRaw = rpcs3_ios_core_last_installed_boot_path();
        const QString installedBootPath = installedBootPathRaw
            ? QString::fromUtf8(installedBootPathRaw)
            : QString();

        if (QAction* refresh = window.findChild<QAction*>(QStringLiteral("refreshGameListAct")))
            refresh->trigger();

        if (installedBootPath.isEmpty())
        {
            QMessageBox::information(
                &window,
                QObject::tr("PKG Installed"),
                QObject::tr("RPCS3 installed the package into dev_hdd0 successfully, but the package did not return a directly bootable path.\n\n%1")
                    .arg(installDiagnostics.message ? QString::fromUtf8(installDiagnostics.message) : QString()));
            return;
        }

        if (!attachVisibleRenderSurface(window, renderHost))
        {
            QMessageBox::critical(
                &window,
                QObject::tr("Renderer Surface Missing"),
                QObject::tr("The package installed, but RPCS3 could not attach its iOS CAMetalLayer surface.\n\n%1")
                    .arg(diagnosticsMessage()));
            return;
        }

        window.statusBar()->showMessage(QObject::tr("Booting installed title through upstream Emu.BootGame and VKGSRender…"));
        QApplication::setOverrideCursor(QCursor(Qt::WaitCursor));
        const int booted = rpcs3_ios_core_boot_elf(installedBootPath.toUtf8().constData());
        QApplication::restoreOverrideCursor();

        const RPCS3IOSCoreDiagnostics bootDiagnostics = rpcs3_ios_core_diagnostics();
        if (!booted)
        {
            setGameSurfaceVisible(window, renderHost, false);
            QMessageBox::critical(
                &window,
                QObject::tr("Installed PKG Boot Failed"),
                QObject::tr("Installed path: %1\n\n%2")
                    .arg(installedBootPath,
                         bootDiagnostics.message
                             ? QString::fromUtf8(bootDiagnostics.message)
                             : QObject::tr("RPCS3 returned no boot diagnostic.")));
            return;
        }

        window.statusBar()->showMessage(
            QObject::tr("Installed title started through RPCS3 Vulkan over MoltenVK"), 6000);
    });

    if (QAction* stopAction = window.findChild<QAction*>(QStringLiteral("sysStopAct")))
    {
        QObject::connect(stopAction, &QAction::triggered, &window, [&window, renderHost]()
        {
            setGameSurfaceVisible(window, renderHost, false);
        });
    }
}

void showFirmwareOnboarding(RPCS3QtMainWindow& window)
{
    if (rpcs3_ios_core_firmware_ready())
        return;

    const QMessageBox::StandardButton result = QMessageBox::question(
        &window,
        QObject::tr("Install PS3 Firmware"),
        QObject::tr("RPCS3 needs an official PS3UPDAT.PUP before PKG applications such as PKGi can be installed and booted. Firmware is installed once and remains in the app's dev_flash storage.\n\nInstall firmware now?"),
        QMessageBox::Yes | QMessageBox::No,
        QMessageBox::Yes);
    if (result == QMessageBox::Yes)
    {
        if (QAction* firmwareAction = window.findChild<QAction*>(QStringLiteral("bootInstallPupAct")))
            firmwareAction->trigger();
    }
}
} // namespace

int main(int argc, char* argv[])
{
    QApplication application(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("RPCS3"));
    QCoreApplication::setApplicationVersion(QStringLiteral("0.1.0"));
    QCoreApplication::setOrganizationName(QStringLiteral("NightVibes33"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("com.nightvibes33"));
    application.setProperty("RPCS3QtBuildMarker", QString::fromLatin1(RPCS3_QT_BUILD_MARKER));

    const int initialized = rpcs3_ios_core_initialize(nullptr);

    RPCS3QtMainWindow window;
    QWidget* renderHost = createNativeRenderHost(window);
    bindFirmwareFlow(window);
    bindPlayablePackageFlow(window, renderHost);
    window.showMaximized();
    application.processEvents();

    int renderSurfaceAttached = 0;
    if (renderHost)
    {
        const WId nativeId = renderHost->winId();
        renderSurfaceAttached = nativeId
            ? rpcs3_ios_core_set_render_view(reinterpret_cast<void*>(nativeId))
            : 0;
    }

    QObject::connect(&application, &QCoreApplication::aboutToQuit, []()
    {
        rpcs3_ios_core_clear_render_view();
    });

    if (!initialized || !renderSurfaceAttached)
    {
        QTimer::singleShot(0, &window, [&window, initialized, renderSurfaceAttached]()
        {
            const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
            const QString detail = diagnostics.message
                ? QString::fromUtf8(diagnostics.message)
                : QStringLiteral("No diagnostic message was returned.");
            QMessageBox::critical(
                &window,
                QStringLiteral("RPCS3 Runtime Initialization Failed"),
                QStringLiteral("Core initialized: %1\nRenderer surface attached: %2\n\n%3")
                    .arg(initialized ? QStringLiteral("yes") : QStringLiteral("no"),
                         renderSurfaceAttached ? QStringLiteral("yes") : QStringLiteral("no"),
                         detail));
        });
    }
    else
    {
        QTimer::singleShot(0, &window, [&window]() { showFirmwareOnboarding(window); });
    }

    return application.exec();
}
