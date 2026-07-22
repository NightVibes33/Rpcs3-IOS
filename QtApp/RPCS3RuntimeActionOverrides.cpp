#include "RPCS3RuntimeActionOverrides.h"
#include "RPCS3CoreBridge.h"

#include <QAction>
#include <QApplication>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QMainWindow>
#include <QMessageBox>
#include <QStandardPaths>
#include <QStatusBar>
#include <QStringList>

namespace
{
QString dataRoot()
{
    const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    return diagnostics.data_path ? QString::fromUtf8(diagnostics.data_path) : QString();
}

QString uniqueDestination(const QString& directory, const QString& filename)
{
    QDir target(directory);
    QString candidate = target.filePath(filename);
    if (!QFileInfo::exists(candidate))
        return candidate;

    const QFileInfo info(filename);
    const QString base = info.completeBaseName().isEmpty() ? QStringLiteral("item") : info.completeBaseName();
    const QString suffix = info.suffix().isEmpty() ? QString() : QStringLiteral(".") + info.suffix();
    for (int index = 1; index < 10000; ++index)
    {
        candidate = target.filePath(QStringLiteral("%1-%2%3").arg(base).arg(index).arg(suffix));
        if (!QFileInfo::exists(candidate))
            return candidate;
    }
    return target.filePath(QStringLiteral("%1-import%2").arg(base, suffix));
}

QString stageFile(const QString& source, const QString& relativeDirectory, QString& error)
{
    const QString root = dataRoot();
    if (root.isEmpty())
    {
        error = QObject::tr("RPCS3 data storage is not initialized.");
        return {};
    }

    const QFileInfo input(source);
    if (!input.isFile())
    {
        error = QObject::tr("The selected file is not readable.");
        return {};
    }

    const QString directory = QDir(root).filePath(relativeDirectory);
    if (!QDir().mkpath(directory))
    {
        error = QObject::tr("Unable to create %1").arg(directory);
        return {};
    }

    const QString destination = uniqueDestination(directory, input.fileName());
    if (!QFile::copy(input.absoluteFilePath(), destination))
    {
        error = QObject::tr("Unable to copy %1 into the RPCS3 sandbox.").arg(input.fileName());
        return {};
    }
    return destination;
}

bool copyDirectory(const QString& source, const QString& destination, QString& error)
{
    if (!QDir().mkpath(destination))
    {
        error = QObject::tr("Unable to create %1").arg(destination);
        return false;
    }

    QDirIterator iterator(source, QDir::AllEntries | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (iterator.hasNext())
    {
        iterator.next();
        const QFileInfo info = iterator.fileInfo();
        const QString relative = QDir(source).relativeFilePath(info.absoluteFilePath());
        const QString output = QDir(destination).filePath(relative);
        if (info.isDir())
        {
            if (!QDir().mkpath(output))
            {
                error = QObject::tr("Unable to create %1").arg(output);
                return false;
            }
        }
        else if (info.isFile())
        {
            QDir().mkpath(QFileInfo(output).absolutePath());
            if (!QFile::copy(info.absoluteFilePath(), output))
            {
                error = QObject::tr("Unable to copy %1").arg(relative);
                return false;
            }
        }
    }
    return true;
}

QString stageGameDirectory(const QString& source, QString& error)
{
    const QString root = dataRoot();
    const QFileInfo input(source);
    if (root.isEmpty() || !input.isDir())
    {
        error = QObject::tr("The selected game directory is unavailable.");
        return {};
    }

    const QString parent = QDir(root).filePath(QStringLiteral("imports/games"));
    QDir().mkpath(parent);
    const QString destination = uniqueDestination(parent, input.fileName());
    return copyDirectory(input.absoluteFilePath(), destination, error) ? destination : QString();
}

void showCoreResult(QMainWindow* window, const QString& title, bool success)
{
    const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    const QString message = diagnostics.message ? QString::fromUtf8(diagnostics.message) : QString();
    if (success)
    {
        if (window->statusBar())
            window->statusBar()->showMessage(message.isEmpty() ? title : message, 7000);
    }
    else
    {
        QMessageBox::critical(window, title,
            message.isEmpty() ? QObject::tr("RPCS3 rejected the operation.") : message);
    }
}

template <typename Handler>
void overrideAction(QMainWindow* window, const char* objectName, Handler&& handler)
{
    QAction* action = window->findChild<QAction*>(QString::fromLatin1(objectName));
    if (!action)
        return;
    QObject::disconnect(action, nullptr, window, nullptr);
    QObject::connect(action, &QAction::triggered, window, std::forward<Handler>(handler));
}
} // namespace

void RPCS3InstallRuntimeActionOverrides(QMainWindow* window)
{
    if (!window)
        return;

    overrideAction(window, "sysPauseAct", [window]
    {
        if (rpcs3_ios_core_operation_available(RPCS3IOSCoreOperationPause))
            showCoreResult(window, QObject::tr("Pause"), rpcs3_ios_core_pause());
        else if (rpcs3_ios_core_operation_available(RPCS3IOSCoreOperationResume))
            showCoreResult(window, QObject::tr("Resume"), rpcs3_ios_core_resume());
        else
            showCoreResult(window, QObject::tr("Pause / Resume"), false);
    });

    overrideAction(window, "sysRebootAct", [window]
    {
        showCoreResult(window, QObject::tr("Restart"), rpcs3_ios_core_restart());
    });

    overrideAction(window, "bootVSHAct", [window]
    {
        showCoreResult(window, QObject::tr("Boot VSH / XMB"), rpcs3_ios_core_boot_vsh());
    });

    overrideAction(window, "bootIsoAct", [window]
    {
        const QString selected = QFileDialog::getOpenFileName(window, QObject::tr("Boot PS3 ISO"),
            QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
            QObject::tr("PS3 ISO (*.iso *.ISO);;All files (*)"));
        if (selected.isEmpty())
            return;
        QString error;
        const QString staged = stageFile(selected, QStringLiteral("disc"), error);
        if (staged.isEmpty())
        {
            QMessageBox::critical(window, QObject::tr("Boot ISO"), error);
            return;
        }
        showCoreResult(window, QObject::tr("Boot ISO"), rpcs3_ios_core_boot_path(staged.toUtf8().constData()));
    });

    overrideAction(window, "addIsoGamesAct", [window]
    {
        const QStringList selected = QFileDialog::getOpenFileNames(window, QObject::tr("Add PS3 ISOs"),
            QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
            QObject::tr("PS3 ISO (*.iso *.ISO);;All files (*)"));
        if (selected.isEmpty())
            return;

        int stagedCount = 0;
        QString error;
        for (const QString& source : selected)
        {
            if (!stageFile(source, QStringLiteral("disc"), error).isEmpty())
                ++stagedCount;
        }
        if (stagedCount == 0)
            QMessageBox::critical(window, QObject::tr("Add ISOs"), error);
        else if (window->statusBar())
            window->statusBar()->showMessage(QObject::tr("Added %1 ISO(s) to the RPCS3 game list storage.").arg(stagedCount), 7000);
    });

    overrideAction(window, "addGamesAct", [window]
    {
        const QString selected = QFileDialog::getExistingDirectory(window, QObject::tr("Add PS3 Game Folder"),
            QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation));
        if (selected.isEmpty())
            return;
        QString error;
        const QString staged = stageGameDirectory(selected, error);
        if (staged.isEmpty())
        {
            QMessageBox::critical(window, QObject::tr("Add Game"), error);
            return;
        }
        showCoreResult(window, QObject::tr("Add Game"), rpcs3_ios_core_add_game(staged.toUtf8().constData()));
    });

    overrideAction(window, "bootInstallPkgAct", [window]
    {
        const QStringList selected = QFileDialog::getOpenFileNames(window, QObject::tr("Install Packages and Licenses"),
            QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
            QObject::tr("RPCS3 packages (*.pkg *.PKG *.rap *.RAP *.edat *.EDAT);;All files (*)"));
        if (selected.isEmpty())
            return;

        bool success = true;
        QString error;
        for (const QString& source : selected)
        {
            const QString suffix = QFileInfo(source).suffix().toLower();
            if (suffix == QStringLiteral("pkg"))
            {
                const QString staged = stageFile(source, QStringLiteral("packages"), error);
                success = !staged.isEmpty() && rpcs3_ios_core_install_package(staged.toUtf8().constData()) && success;
            }
            else
            {
                const QString staged = stageFile(source, QStringLiteral("dev_hdd0/home/00000001/exdata"), error);
                success = !staged.isEmpty() && success;
            }
        }
        showCoreResult(window, QObject::tr("Install Packages / Licenses"), success);
    });

    overrideAction(window, "bootInstallPupAct", [window]
    {
        const QString selected = QFileDialog::getOpenFileName(window, QObject::tr("Install PS3 Firmware"),
            QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
            QObject::tr("PS3 firmware (PS3UPDAT.PUP *.pup *.PUP);;All files (*)"));
        if (selected.isEmpty())
            return;
        QString error;
        const QString staged = stageFile(selected, QStringLiteral("firmware"), error);
        if (staged.isEmpty())
        {
            QMessageBox::critical(window, QObject::tr("Install Firmware"), error);
            return;
        }
        showCoreResult(window, QObject::tr("Install Firmware"), rpcs3_ios_core_install_firmware(staged.toUtf8().constData()));
    });

    overrideAction(window, "insertDiscAct", [window]
    {
        const QString selected = QFileDialog::getOpenFileName(window, QObject::tr("Insert PS3 Disc Image"),
            QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
            QObject::tr("PS3 ISO (*.iso *.ISO);;All files (*)"));
        if (selected.isEmpty())
            return;
        QString error;
        const QString staged = stageFile(selected, QStringLiteral("disc/inserted"), error);
        if (staged.isEmpty())
        {
            QMessageBox::critical(window, QObject::tr("Insert Disc"), error);
            return;
        }
        showCoreResult(window, QObject::tr("Insert Disc"), rpcs3_ios_core_insert_disc(staged.toUtf8().constData()));
    });

    overrideAction(window, "ejectDiscAct", [window]
    {
        showCoreResult(window, QObject::tr("Eject Disc"), rpcs3_ios_core_eject_disc());
    });
}
