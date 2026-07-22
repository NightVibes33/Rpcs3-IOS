#pragma once

#include <QMainWindow>
#include <QString>
#include <QStringList>
#include <memory>

QT_BEGIN_NAMESPACE
class QAction;
class QListWidget;
class QListWidgetItem;
class QWidget;
namespace Ui { class main_window; }
QT_END_NAMESPACE

class RPCS3QtMainWindow final : public QMainWindow
{
    Q_OBJECT

public:
    explicit RPCS3QtMainWindow(QWidget* parent = nullptr);
    ~RPCS3QtMainWindow() override;

    QWidget* renderHostWidget() const;
    void setRenderSurfaceActive(bool active);

private:
    std::unique_ptr<Ui::main_window> m_ui;
    QListWidget* m_gameList = nullptr;
    QWidget* m_renderHost = nullptr;
    QString m_dataRoot;

    void configureMainWindow();
    void bindUpstreamActions();
    void handleAction(const QString& identifier);
    void reloadGameList();
    void applySearch(const QString& query);
    void applyIconSize(int value);
    void setGridMode(bool enabled);

    QString locateBootExecutable(const QString& path) const;
    QString stageFile(const QString& sourcePath, const QString& destinationFolder, QString* errorMessage = nullptr) const;
    QString stageDirectory(const QString& sourcePath, const QString& destinationFolder, QString* errorMessage = nullptr) const;
    bool copyDirectoryRecursively(const QString& sourcePath, const QString& destinationPath, QString* errorMessage) const;

    void chooseAndBootExecutable(const QString& title);
    void chooseAndStageFiles(const QString& title, const QString& destinationFolder, bool multiple, bool bootFirst);
    void chooseAndStageGameDirectory();
    void bootVsh();
    void bootPath(const QString& path, const QString& title);
    void showCoreResult(const QString& title, int accepted);
    void showDiagnostics();
    void showUpstreamDialog(const QString& fileName, const QString& preferredPage = QString());
    void showPending(const QString& identifier, const QString& detail = QString());
    void openUrl(const QString& url);

private slots:
    void bootSelectedItem(QListWidgetItem* item);
};
