#pragma once

#include "../Renderers/RPCS3RendererBackend.h"

#include <QElapsedTimer>
#include <QTimer>
#include <QWidget>
#include <memory>

class QHideEvent;
class QResizeEvent;
class QShowEvent;

class RPCS3RenderWidget final : public QWidget
{
    Q_OBJECT

public:
    explicit RPCS3RenderWidget(QWidget* parent = nullptr);
    ~RPCS3RenderWidget() override;

    rpcs3::ios::render::backend_kind backendKind() const noexcept;
    bool setBackend(rpcs3::ios::render::backend_kind kind);
    bool startRenderer();
    void stopRenderer();
    void registerAsGameSurface();
    QString statusText() const;

signals:
    void rendererStatusChanged(const QString& status);

protected:
    void showEvent(QShowEvent* event) override;
    void hideEvent(QHideEvent* event) override;
    void resizeEvent(QResizeEvent* event) override;

private slots:
    void presentFrame();

private:
    rpcs3::ios::render::surface_config surfaceConfig() const;
    void publishStatus(const QString& prefix = QString());

    rpcs3::ios::render::backend_kind m_kind = rpcs3::ios::render::backend_kind::vulkan;
    std::unique_ptr<rpcs3::ios::render::renderer_backend> m_backend;
    QTimer m_frameTimer;
    QElapsedTimer m_elapsed;
    QString m_lastError;
};
