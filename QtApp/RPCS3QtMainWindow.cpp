#include "RPCS3QtMainWindow.h"

#include "RPCS3CoreBridge.h"
#include "ui_main_window.h"

#include <QAction>
#include <QApplication>
#include <QDesktopServices>
#include <QDialog>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QHash>
#include <QHBoxLayout>
#include <QIcon>
#include <QLabel>
#include <QLineEdit>
#include <QListView>
#include <QListWidget>
#include <QMenuBar>
#include <QMessageBox>
#include <QSet>
#include <QSize>
#include <QSlider>
#include <QStandardPaths>
#include <QStatusBar>
#include <QTabWidget>
#include <QTimer>
#include <QToolBar>
#include <QUiLoader>
#include <QUrl>
#include <QVBoxLayout>

namespace
{
QString fromUtf8(const char* value)
{
    return value ? QString::fromUtf8(value) : QString();
}

QString uniqueDestination(const QString& directory, const QString& name)
{
    QDir destination(directory);
    QString candidate = destination.filePath(name);
    if (!QFileInfo::exists(candidate))
        return candidate;

    const QFileInfo info(name);
    const QString base = info.completeBaseName().isEmpty() ? QStringLiteral("item") : info.completeBaseName();
    const QString suffix = info.suffix().isEmpty() ? QString() : QStringLiteral(".") + info.suffix();
    for (int index = 1; index < 10000; ++index)
    {
        candidate = destination.filePath(QStringLiteral("%1-%2%3").arg(base).arg(index).arg(suffix));
        if (!QFileInfo::exists(candidate))
            return candidate;
    }
    return destination.filePath(QStringLiteral("%1-%2%3").arg(base, QString::number(QDateTime::currentMSecsSinceEpoch()), suffix));
}

bool isBootCandidate(const QFileInfo& info)
{
    const QString name = info.fileName().toLower();
    const QString suffix = info.suffix().toLower();
    return name == QStringLiteral("eboot.bin") || name.endsWith(QStringLiteral(".self")) ||
           suffix == QStringLiteral("elf") || suffix == QStringLiteral("self") ||
           suffix == QStringLiteral("iso") || suffix == QStringLiteral("pkg");
}
}

RPCS3QtMainWindow::RPCS3QtMainWindow(QWidget* parent)
    : QMainWindow(parent),
      m_ui(std::make_unique<Ui::main_window>())
{
    m_ui->setupUi(this);
    m_dataRoot = fromUtf8(rpcs3_ios_core_diagnostics().data_path);
    configureMainWindow();
    bindUpstreamActions();
    reloadGameList();
}

RPCS3QtMainWindow::~RPCS3QtMainWindow() = default;

void RPCS3QtMainWindow::configureMainWindow()
{
    setWindowTitle(QStringLiteral("RPCS3"));
    setMinimumSize(QSize(320, 480));
    resize(QSize(1024, 768));

    if (m_ui->menuBar)
    {
        m_ui->menuBar->setNativeMenuBar(false);
        m_ui->menuBar->setStyleSheet(QStringLiteral(
            "QMenuBar::item { padding: 8px 10px; }"
            "QMenu::item { padding: 10px 22px 10px 18px; }"));
    }

    for (QToolBar* toolbar : findChildren<QToolBar*>())
    {
        toolbar->setMovable(false);
        toolbar->setFloatable(false);
        toolbar->setIconSize(QSize(26, 26));
    }

    QWidget* central = m_ui->centralWidget;
    auto* rootLayout = new QVBoxLayout(central);
    rootLayout->setContentsMargins(12, 10, 12, 10);
    rootLayout->setSpacing(10);

    auto* controls = new QHBoxLayout();
    controls->setSpacing(8);
    m_ui->sizeSliderContainer->setParent(central);
    m_ui->mw_searchbar->setParent(central);
    m_ui->mw_searchbar->setFrame(true);
    m_ui->mw_searchbar->setClearButtonEnabled(true);
    controls->addWidget(m_ui->sizeSliderContainer, 0);
    controls->addWidget(m_ui->mw_searchbar, 1);
    rootLayout->addLayout(controls);

    m_gameList = new QListWidget(central);
    m_gameList->setObjectName(QStringLiteral("rpcs3GameList"));
    m_gameList->setSelectionMode(QAbstractItemView::SingleSelection);
    m_gameList->setResizeMode(QListView::Adjust);
    m_gameList->setMovement(QListView::Static);
    m_gameList->setSpacing(10);
    m_gameList->setWordWrap(true);
    m_gameList->setUniformItemSizes(false);
    rootLayout->addWidget(m_gameList, 1);

    m_ui->sizeSlider->setRange(48, 220);
    m_ui->sizeSlider->setValue(104);
    applyIconSize(m_ui->sizeSlider->value());
    setGridMode(true);

    connect(m_ui->mw_searchbar, &QLineEdit::textChanged, this, &RPCS3QtMainWindow::applySearch);
    connect(m_ui->sizeSlider, &QSlider::valueChanged, this, &RPCS3QtMainWindow::applyIconSize);
    connect(m_gameList, &QListWidget::itemActivated, this, &RPCS3QtMainWindow::bootSelectedItem);

    statusBar()->showMessage(QStringLiteral("RPCS3 Qt iOS — upstream main_window.ui loaded"));
}

void RPCS3QtMainWindow::bindUpstreamActions()
{
    const QList<QAction*> actions = findChildren<QAction*>();
    for (QAction* action : actions)
    {
        if (!action || action->objectName().isEmpty() || action->menu())
            continue;
        connect(action, &QAction::triggered, this, [this, action]() {
            handleAction(action->objectName());
        });
    }
}

void RPCS3QtMainWindow::handleAction(const QString& identifier)
{
    static const QHash<QString, QPair<QString, QString>> dialogs = {
        {QStringLiteral("confCPUAct"), {QStringLiteral("settings_dialog.ui"), QStringLiteral("coreTab")}},
        {QStringLiteral("confGPUAct"), {QStringLiteral("settings_dialog.ui"), QStringLiteral("gpuTab")}},
        {QStringLiteral("confAudioAct"), {QStringLiteral("settings_dialog.ui"), QStringLiteral("audioTab")}},
        {QStringLiteral("confIOAct"), {QStringLiteral("settings_dialog.ui"), QStringLiteral("inputTab")}},
        {QStringLiteral("confSystemAct"), {QStringLiteral("settings_dialog.ui"), QStringLiteral("systemTab")}},
        {QStringLiteral("confNetwrkAct"), {QStringLiteral("settings_dialog.ui"), QStringLiteral("networkTab")}},
        {QStringLiteral("confAdvAct"), {QStringLiteral("settings_dialog.ui"), QStringLiteral("advancedTab")}},
        {QStringLiteral("confEmuAct"), {QStringLiteral("settings_dialog.ui"), QStringLiteral("emulatorTab")}},
        {QStringLiteral("confGuiAct"), {QStringLiteral("settings_dialog.ui"), QStringLiteral("guiTab")}},
        {QStringLiteral("confPadsAct"), {QStringLiteral("pad_settings_dialog.ui"), QString()}},
        {QStringLiteral("confCamerasAct"), {QStringLiteral("camera_settings_dialog.ui"), QString()}},
        {QStringLiteral("actionPS_Move_Tracker"), {QStringLiteral("ps_move_tracker_dialog.ui"), QString()}},
        {QStringLiteral("confShortcutsAct"), {QStringLiteral("shortcut_dialog.ui"), QString()}},
        {QStringLiteral("toolsVfsDialogAct"), {QStringLiteral("vfs_tool_dialog.ui"), QString()}},
        {QStringLiteral("confVFSDialogAct"), {QStringLiteral("vfs_dialog.ui"), QString()}},
        {QStringLiteral("actionManage_Game_Patches"), {QStringLiteral("patch_manager_dialog.ui"), QString()}},
        {QStringLiteral("patchCreatorAct"), {QStringLiteral("patch_creator_dialog.ui"), QString()}},
        {QStringLiteral("actionMusic_Player"), {QStringLiteral("music_player_dialog.ui"), QString()}},
        {QStringLiteral("welcomeAct"), {QStringLiteral("welcome_dialog.ui"), QString()}},
        {QStringLiteral("aboutAct"), {QStringLiteral("about_dialog.ui"), QString()}}
    };

    if (dialogs.contains(identifier))
    {
        const auto route = dialogs.value(identifier);
        showUpstreamDialog(route.first, route.second);
        return;
    }

    if (identifier == QStringLiteral("bootGameAct") || identifier == QStringLiteral("bootElfAct") || identifier == QStringLiteral("bootTestAct"))
    {
        chooseAndBootExecutable(identifier == QStringLiteral("bootGameAct") ? tr("Boot Game") : tr("Boot SELF/ELF"));
        return;
    }
    if (identifier == QStringLiteral("addGamesAct"))
    {
        chooseAndStageGameDirectory();
        return;
    }
    if (identifier == QStringLiteral("bootIsoAct") || identifier == QStringLiteral("addIsoGamesAct"))
    {
        chooseAndStageFiles(tr("Import PS3 ISO"), QStringLiteral("disc"), identifier == QStringLiteral("addIsoGamesAct"), false);
        return;
    }
    if (identifier == QStringLiteral("bootInstallPkgAct"))
    {
        chooseAndStageFiles(tr("Install Packages / RAPs / EDATs"), QStringLiteral("packages"), true, false);
        return;
    }
    if (identifier == QStringLiteral("bootInstallPupAct"))
    {
        chooseAndStageFiles(tr("Install PS3 Firmware"), QStringLiteral("firmware"), false, false);
        return;
    }
    if (identifier == QStringLiteral("actionManage_RAP_Licenses"))
    {
        chooseAndStageFiles(tr("Import RAP Licenses"), QStringLiteral("keys"), true, false);
        return;
    }
    if (identifier == QStringLiteral("bootSavestateAct"))
    {
        chooseAndStageFiles(tr("Boot Savestate"), QStringLiteral("savestates"), false, false);
        return;
    }
    if (identifier == QStringLiteral("insertDiscAct"))
    {
        chooseAndStageFiles(tr("Insert Disc"), QStringLiteral("disc/inserted"), false, false);
        return;
    }
    if (identifier == QStringLiteral("ejectDiscAct"))
    {
        QDir inserted(QDir(m_dataRoot).filePath(QStringLiteral("disc/inserted")));
        inserted.removeRecursively();
        statusBar()->showMessage(tr("Inserted disc staging directory cleared"), 4000);
        return;
    }
    if (identifier == QStringLiteral("bootVSHAct"))
    {
        bootVsh();
        return;
    }
    if (identifier == QStringLiteral("sysStopAct"))
    {
        rpcs3_ios_core_stop();
        showCoreResult(tr("Stop"), 1);
        return;
    }
    if (identifier == QStringLiteral("refreshGameListAct") || identifier == QStringLiteral("cleanUpGameListAct"))
    {
        reloadGameList();
        return;
    }
    if (identifier == QStringLiteral("setListModeAct"))
    {
        setGridMode(false);
        return;
    }
    if (identifier == QStringLiteral("setGridModeAct"))
    {
        setGridMode(true);
        return;
    }
    if (identifier == QStringLiteral("setIconSizeTinyAct")) { m_ui->sizeSlider->setValue(56); return; }
    if (identifier == QStringLiteral("setIconSizeSmallAct")) { m_ui->sizeSlider->setValue(80); return; }
    if (identifier == QStringLiteral("setIconSizeMediumAct")) { m_ui->sizeSlider->setValue(112); return; }
    if (identifier == QStringLiteral("setIconSizeLargeAct")) { m_ui->sizeSlider->setValue(172); return; }
    if (identifier == QStringLiteral("actionLog_Viewer"))
    {
        showDiagnostics();
        return;
    }
    if (identifier == QStringLiteral("quickstartAct") || identifier == QStringLiteral("supportAct"))
    {
        openUrl(QStringLiteral("https://rpcs3.net/quickstart"));
        return;
    }
    if (identifier == QStringLiteral("compatibilityAct"))
    {
        openUrl(QStringLiteral("https://rpcs3.net/compatibility"));
        return;
    }
    if (identifier == QStringLiteral("reportIssueAct"))
    {
        openUrl(QStringLiteral("https://github.com/RPCS3/rpcs3/issues"));
        return;
    }
    if (identifier == QStringLiteral("exitAct") || identifier == QStringLiteral("exitAndSaveLogAct"))
    {
        QApplication::quit();
        return;
    }

    showPending(identifier);
}

void RPCS3QtMainWindow::reloadGameList()
{
    if (!m_gameList)
        return;

    m_gameList->clear();
    QSet<QString> seen;

    const QStringList folderRoots = {
        QDir(m_dataRoot).filePath(QStringLiteral("dev_hdd0/game")),
        QDir(m_dataRoot).filePath(QStringLiteral("imports"))
    };

    for (const QString& root : folderRoots)
    {
        QDir directory(root);
        if (!directory.exists())
            continue;
        const QFileInfoList entries = directory.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase);
        for (const QFileInfo& entry : entries)
        {
            QString bootPath = locateBootExecutable(entry.absoluteFilePath());
            if (bootPath.isEmpty() && !isBootCandidate(entry))
                continue;
            const QString representedPath = entry.isDir() ? entry.absoluteFilePath() : bootPath;
            const QString canonical = QFileInfo(representedPath).absoluteFilePath();
            if (seen.contains(canonical))
                continue;
            seen.insert(canonical);

            QString title = entry.completeBaseName();
            if (title.isEmpty())
                title = entry.fileName();
            auto* item = new QListWidgetItem(title, m_gameList);
            item->setData(Qt::UserRole, representedPath);
            item->setToolTip(representedPath);

            QString iconPath;
            if (entry.isDir())
            {
                const QStringList iconCandidates = {
                    QDir(entry.absoluteFilePath()).filePath(QStringLiteral("ICON0.PNG")),
                    QDir(entry.absoluteFilePath()).filePath(QStringLiteral("PS3_GAME/ICON0.PNG"))
                };
                for (const QString& candidate : iconCandidates)
                    if (QFileInfo::exists(candidate)) { iconPath = candidate; break; }
            }
            if (!iconPath.isEmpty())
                item->setIcon(QIcon(iconPath));
            else
                item->setIcon(style()->standardIcon(QStyle::SP_ComputerIcon));
        }
    }

    const QStringList fileRoots = {
        QDir(m_dataRoot).filePath(QStringLiteral("disc")),
        QDir(m_dataRoot).filePath(QStringLiteral("imports/boot"))
    };
    for (const QString& root : fileRoots)
    {
        if (!QDir(root).exists())
            continue;
        QDirIterator iterator(root, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        int count = 0;
        while (iterator.hasNext() && count < 2000)
        {
            iterator.next();
            const QFileInfo info = iterator.fileInfo();
            if (!isBootCandidate(info))
                continue;
            const QString path = info.absoluteFilePath();
            if (seen.contains(path))
                continue;
            seen.insert(path);
            auto* item = new QListWidgetItem(info.completeBaseName(), m_gameList);
            item->setData(Qt::UserRole, path);
            item->setToolTip(path);
            item->setIcon(style()->standardIcon(QStyle::SP_DriveDVDIcon));
            ++count;
        }
    }

    applySearch(m_ui->mw_searchbar->text());
    statusBar()->showMessage(tr("%1 RPCS3 content item(s)").arg(m_gameList->count()), 4000);
}

void RPCS3QtMainWindow::applySearch(const QString& query)
{
    if (!m_gameList)
        return;
    const QString normalized = query.trimmed();
    for (int row = 0; row < m_gameList->count(); ++row)
    {
        QListWidgetItem* item = m_gameList->item(row);
        const bool visible = normalized.isEmpty() || item->text().contains(normalized, Qt::CaseInsensitive) ||
                             item->toolTip().contains(normalized, Qt::CaseInsensitive);
        item->setHidden(!visible);
    }
}

void RPCS3QtMainWindow::applyIconSize(int value)
{
    if (!m_gameList)
        return;
    m_gameList->setIconSize(QSize(value, value));
    m_gameList->setGridSize(QSize(qMax(value + 56, 120), qMax(value + 68, 140)));
}

void RPCS3QtMainWindow::setGridMode(bool enabled)
{
    if (!m_gameList)
        return;
    m_gameList->setViewMode(enabled ? QListView::IconMode : QListView::ListMode);
    m_gameList->setFlow(enabled ? QListView::LeftToRight : QListView::TopToBottom);
    m_gameList->setWrapping(enabled);
    m_gameList->setGridSize(enabled ? QSize(qMax(m_ui->sizeSlider->value() + 56, 120), qMax(m_ui->sizeSlider->value() + 68, 140)) : QSize());
}

QString RPCS3QtMainWindow::locateBootExecutable(const QString& path) const
{
    const QFileInfo info(path);
    if (info.isFile())
        return isBootCandidate(info) ? info.absoluteFilePath() : QString();
    if (!info.isDir())
        return QString();

    const QStringList candidates = {
        QDir(path).filePath(QStringLiteral("EBOOT.BIN")),
        QDir(path).filePath(QStringLiteral("USRDIR/EBOOT.BIN")),
        QDir(path).filePath(QStringLiteral("PS3_GAME/USRDIR/EBOOT.BIN")),
        QDir(path).filePath(QStringLiteral("vsh/module/vsh.self"))
    };
    for (const QString& candidate : candidates)
        if (QFileInfo(candidate).isFile()) return candidate;
    return QString();
}

QString RPCS3QtMainWindow::stageFile(const QString& sourcePath, const QString& destinationFolder, QString* errorMessage) const
{
    if (m_dataRoot.isEmpty())
    {
        if (errorMessage) *errorMessage = tr("RPCS3 data root is unavailable.");
        return QString();
    }
    const QFileInfo source(sourcePath);
    if (!source.isFile())
    {
        if (errorMessage) *errorMessage = tr("The selected item is not a readable file.");
        return QString();
    }
    const QString directory = QDir(m_dataRoot).filePath(destinationFolder);
    if (!QDir().mkpath(directory))
    {
        if (errorMessage) *errorMessage = tr("Unable to create %1").arg(directory);
        return QString();
    }
    const QString destination = uniqueDestination(directory, source.fileName());
    if (!QFile::copy(source.absoluteFilePath(), destination))
    {
        if (errorMessage) *errorMessage = tr("Unable to copy %1 into the RPCS3 sandbox.").arg(source.fileName());
        return QString();
    }
    return destination;
}

QString RPCS3QtMainWindow::stageDirectory(const QString& sourcePath, const QString& destinationFolder, QString* errorMessage) const
{
    const QFileInfo source(sourcePath);
    if (!source.isDir())
    {
        if (errorMessage) *errorMessage = tr("The selected item is not a directory.");
        return QString();
    }
    const QString parent = QDir(m_dataRoot).filePath(destinationFolder);
    if (!QDir().mkpath(parent))
    {
        if (errorMessage) *errorMessage = tr("Unable to create %1").arg(parent);
        return QString();
    }
    const QString destination = uniqueDestination(parent, source.fileName());
    return copyDirectoryRecursively(source.absoluteFilePath(), destination, errorMessage) ? destination : QString();
}

bool RPCS3QtMainWindow::copyDirectoryRecursively(const QString& sourcePath, const QString& destinationPath, QString* errorMessage) const
{
    if (!QDir().mkpath(destinationPath))
    {
        if (errorMessage) *errorMessage = tr("Unable to create %1").arg(destinationPath);
        return false;
    }
    QDirIterator iterator(sourcePath, QDir::AllEntries | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (iterator.hasNext())
    {
        iterator.next();
        const QFileInfo info = iterator.fileInfo();
        const QString relative = QDir(sourcePath).relativeFilePath(info.absoluteFilePath());
        const QString target = QDir(destinationPath).filePath(relative);
        if (info.isDir())
        {
            if (!QDir().mkpath(target))
            {
                if (errorMessage) *errorMessage = tr("Unable to create %1").arg(target);
                return false;
            }
        }
        else if (info.isFile())
        {
            QDir().mkpath(QFileInfo(target).absolutePath());
            if (!QFile::copy(info.absoluteFilePath(), target))
            {
                if (errorMessage) *errorMessage = tr("Unable to copy %1").arg(relative);
                return false;
            }
        }
    }
    return true;
}

void RPCS3QtMainWindow::chooseAndBootExecutable(const QString& title)
{
    const QString selected = QFileDialog::getOpenFileName(this, title, QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation), tr("PS3 executables (*.bin *.elf *.self);;All files (*)"));
    if (selected.isEmpty())
        return;
    QString error;
    const QString staged = stageFile(selected, QStringLiteral("imports/boot"), &error);
    if (staged.isEmpty())
    {
        QMessageBox::critical(this, title, error);
        return;
    }
    bootPath(staged, title);
    reloadGameList();
}

void RPCS3QtMainWindow::chooseAndStageFiles(const QString& title, const QString& destinationFolder, bool multiple, bool bootFirst)
{
    QStringList selected;
    if (multiple)
        selected = QFileDialog::getOpenFileNames(this, title, QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation), tr("All files (*)"));
    else
    {
        const QString single = QFileDialog::getOpenFileName(this, title, QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation), tr("All files (*)"));
        if (!single.isEmpty()) selected << single;
    }
    if (selected.isEmpty())
        return;

    QStringList staged;
    QString lastError;
    for (const QString& source : selected)
    {
        const QString destination = stageFile(source, destinationFolder, &lastError);
        if (!destination.isEmpty()) staged << destination;
    }
    if (bootFirst && !staged.isEmpty())
        bootPath(staged.first(), title);
    else if (!staged.isEmpty())
    {
        const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
        const bool executionCapable = diagnostics.capability_level == RPCS3IOSCoreCapabilityExecutionCapable;
        const QString detail = executionCapable
            ? tr("%1 file(s) staged in %2.").arg(staged.size()).arg(destinationFolder)
            : tr("%1 file(s) staged in %2. The current core archive is still classified as %3, so the upstream installer/runtime operation cannot execute yet.")
                  .arg(staged.size()).arg(destinationFolder, fromUtf8(diagnostics.build_classification));
        QMessageBox::information(this, title, detail);
    }
    else if (!lastError.isEmpty())
        QMessageBox::critical(this, title, lastError);
    reloadGameList();
}

void RPCS3QtMainWindow::chooseAndStageGameDirectory()
{
    const QString selected = QFileDialog::getExistingDirectory(this, tr("Add PS3 Game Folder"), QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation));
    if (selected.isEmpty())
        return;
    QString error;
    const QString staged = stageDirectory(selected, QStringLiteral("imports"), &error);
    if (staged.isEmpty())
        QMessageBox::critical(this, tr("Add Games"), error);
    else
        statusBar()->showMessage(tr("Imported %1").arg(QFileInfo(staged).fileName()), 5000);
    reloadGameList();
}

void RPCS3QtMainWindow::bootVsh()
{
    const QStringList candidates = {
        QDir(m_dataRoot).filePath(QStringLiteral("dev_flash/vsh/module/vsh.self")),
        QDir(m_dataRoot).filePath(QStringLiteral("firmware/dev_flash/vsh/module/vsh.self")),
        QDir(m_dataRoot).filePath(QStringLiteral("imports/dev_flash/vsh/module/vsh.self"))
    };
    for (const QString& candidate : candidates)
    {
        if (QFileInfo(candidate).isFile())
        {
            bootPath(candidate, tr("Boot VSH/XMB"));
            return;
        }
    }
    QMessageBox::warning(this, tr("Boot VSH/XMB"), tr("vsh.self was not found in the RPCS3 dev_flash tree. Install or extract PS3 firmware first."));
}

void RPCS3QtMainWindow::bootPath(const QString& path, const QString& title)
{
    const QString executable = locateBootExecutable(path);
    if (executable.isEmpty())
    {
        QMessageBox::warning(this, title, tr("No EBOOT.BIN, SELF, or ELF executable was found at the selected path."));
        return;
    }
    const int accepted = rpcs3_ios_core_boot_elf(executable.toUtf8().constData());
    showCoreResult(title, accepted);
}

void RPCS3QtMainWindow::showCoreResult(const QString& title, int accepted)
{
    const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    const QString result = accepted ? tr("Accepted") : tr("Failed");
    QMessageBox::information(this, title,
        tr("Core bridge result: %1\nClassification: %2\nExecution capable: %3\n\n%4")
            .arg(result,
                 fromUtf8(diagnostics.build_classification),
                 diagnostics.capability_level == RPCS3IOSCoreCapabilityExecutionCapable ? tr("yes") : tr("no"),
                 fromUtf8(diagnostics.message)));
}

void RPCS3QtMainWindow::showDiagnostics()
{
    const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    QMessageBox::information(this, tr("RPCS3 Diagnostics"),
        tr("Upstream revision: %1\nBuild classification: %2\nDirect upstream sources: %3\nPlatform initialized: %4\nPPU: %5\nSPU: %6\nJIT: %7\nRenderer: %8\nData root: %9\n\n%10")
            .arg(fromUtf8(diagnostics.upstream_revision),
                 fromUtf8(diagnostics.build_classification),
                 QString::number(diagnostics.upstream_source_count),
                 diagnostics.platform_initialized ? tr("yes") : tr("no"),
                 diagnostics.ppu_interpreter_available ? tr("ready") : tr("missing"),
                 diagnostics.spu_interpreter_available ? tr("ready") : tr("missing"),
                 diagnostics.jit_available ? tr("ready") : tr("missing"),
                 diagnostics.renderer_available ? tr("ready") : tr("missing"),
                 fromUtf8(diagnostics.data_path),
                 fromUtf8(diagnostics.message)));
}

void RPCS3QtMainWindow::showUpstreamDialog(const QString& fileName, const QString& preferredPage)
{
    QFile source(QStringLiteral(":/rpcs3/ui/") + fileName);
    if (!source.open(QIODevice::ReadOnly))
    {
        showPending(fileName, tr("The upstream Qt Designer document was not bundled."));
        return;
    }

    QUiLoader loader;
    QWidget* widget = loader.load(&source, this);
    source.close();
    if (!widget)
    {
        QMessageBox::warning(this, tr("RPCS3 Qt UI"), tr("Unable to load %1 with Qt UiTools.\n\n%2").arg(fileName, loader.errorString()));
        return;
    }

    widget->setAttribute(Qt::WA_DeleteOnClose, true);
    if (!preferredPage.isEmpty())
    {
        if (QWidget* requested = widget->findChild<QWidget*>(preferredPage))
        {
            QWidget* parent = requested->parentWidget();
            while (parent)
            {
                if (auto* tabs = qobject_cast<QTabWidget*>(parent))
                {
                    const int index = tabs->indexOf(requested);
                    if (index >= 0) tabs->setCurrentIndex(index);
                    break;
                }
                requested = parent;
                parent = parent->parentWidget();
            }
        }
    }

    if (auto* dialog = qobject_cast<QDialog*>(widget))
    {
        dialog->setWindowModality(Qt::ApplicationModal);
        dialog->showMaximized();
    }
    else
    {
        widget->setWindowFlag(Qt::Window, true);
        widget->showMaximized();
    }
}

void RPCS3QtMainWindow::showPending(const QString& identifier, const QString& detail)
{
    const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    const QString reason = detail.isEmpty()
        ? tr("This QAction comes directly from RPCS3's main_window.ui, but the C++ implementation behind it is not linked into the current iOS core archive.")
        : detail;
    QMessageBox::information(this, identifier,
        tr("%1\n\nCurrent core: %2\nExecution capable: %3")
            .arg(reason,
                 fromUtf8(diagnostics.build_classification),
                 diagnostics.capability_level == RPCS3IOSCoreCapabilityExecutionCapable ? tr("yes") : tr("no")));
}

void RPCS3QtMainWindow::openUrl(const QString& url)
{
    QDesktopServices::openUrl(QUrl(url));
}

void RPCS3QtMainWindow::bootSelectedItem(QListWidgetItem* item)
{
    if (!item)
        return;
    bootPath(item->data(Qt::UserRole).toString(), item->text());
}
