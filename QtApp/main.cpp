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
#include <QMessageBox>
#include <QStandardPaths>
#include <QStatusBar>
#include <QTimer>

#ifndef RPCS3_QT_BUILD_MARKER
#define RPCS3_QT_BUILD_MARKER "RPCS3 Qt iOS upstream main_window.ui"
#endif

namespace
{
QString uniquePackageDestination(const QString& directory, const QString& fileName)
{
    QDir destination(directory);
    const QFileInfo source(fileName);
    const QString base = source.completeBaseName().isEmpty()
        ? QStringLiteral("package")
        : source.completeBaseName();
    const QString suffix = source.suffix().isEmpty()
        ? QStringLiteral(".pkg")
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

void bindPlayablePackageFlow(RPCS3QtMainWindow& window)
{
    QAction* installAction = window.findChild<QAction*>(QStringLiteral("bootInstallPkgAct"));
    if (!installAction)
        return;

    // Replace the temporary staging-only handler installed by the generic
    // upstream QAction router with the real package_reader installation path.
    QObject::disconnect(installAction, nullptr, &window, nullptr);
    QObject::connect(installAction, &QAction::triggered, &window, [&window]()
    {
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

        const QString stagedPath = uniquePackageDestination(packageDirectory, QFileInfo(selected).fileName());
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

        window.statusBar()->showMessage(QObject::tr("Booting installed title through upstream Emu.BootGame…"));
        QApplication::setOverrideCursor(QCursor(Qt::WaitCursor));
        const int booted = rpcs3_ios_core_boot_elf(installedBootPath.toUtf8().constData());
        QApplication::restoreOverrideCursor();

        const RPCS3IOSCoreDiagnostics bootDiagnostics = rpcs3_ios_core_diagnostics();
        if (!booted)
        {
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

        QMessageBox::information(
            &window,
            QObject::tr("Installed PKG Boot Started"),
            QObject::tr("RPCS3 installed the package and accepted its boot path through the real upstream Emulator::BootGame pipeline.\n\nInstalled path: %1\n\nGraphics are still using Null RSX, so visible gameplay requires the Metal renderer milestone.\n\n%2")
                .arg(installedBootPath,
                     bootDiagnostics.message
                         ? QString::fromUtf8(bootDiagnostics.message)
                         : QString()));
    });
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
    bindPlayablePackageFlow(window);
    window.showMaximized();

    if (!initialized)
    {
        QTimer::singleShot(0, &window, [&window]() {
            const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
            QMessageBox::critical(&window,
                                  QStringLiteral("RPCS3 Core Initialization Failed"),
                                  diagnostics.message ? QString::fromUtf8(diagnostics.message)
                                                      : QStringLiteral("No diagnostic message was returned."));
        });
    }

    return application.exec();
}
