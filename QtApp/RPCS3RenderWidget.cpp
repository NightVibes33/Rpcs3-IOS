#include "RPCS3RenderWidget.h"

#include <QHideEvent>
#include <QResizeEvent>
#include <QShowEvent>
#include <QtGlobal>

#include <algorithm>
#include <cmath>
#include <cstdint>

using rpcs3::ios::render::backend_kind;
using rpcs3::ios::render::backend_status;
using rpcs3::ios::render::create_renderer_backend;
using rpcs3::ios::render::renderer_backend_compiled;
using rpcs3::ios::render::renderer_backend_name;

RPCS3RenderWidget::RPCS3RenderWidget(QWidget* parent)
    : QWidget(parent)
{
    setObjectName(QStringLiteral("rpcs3RendererSurface"));
    setAttribute(Qt::WA_NativeWindow, true);
    setAttribute(Qt::WA_OpaquePaintEvent, true);
    setAttribute(Qt::WA_NoSystemBackground, true);
    setAutoFillBackground(false);
    setMinimumHeight(220);

    m_frameTimer.setTimerType(Qt::PreciseTimer);
    m_frameTimer.setInterval(16);
    connect(&m_frameTimer, &QTimer::timeout, this, &RPCS3RenderWidget::presentFrame);

    if (!renderer_backend_compiled(m_kind))
        m_kind = backend_kind::metal;
}

RPCS3RenderWidget::~RPCS3RenderWidget()
{
    stopRenderer();
}

backend_kind RPCS3RenderWidget::backendKind() const noexcept
{
    return m_kind;
}

bool RPCS3RenderWidget::setBackend(backend_kind kind)
{
    if (!renderer_backend_compiled(kind))
    {
        m_lastError = tr("%1 was not compiled into this build.").arg(QString::fromUtf8(renderer_backend_name(kind)));
        publishStatus();
        return false;
    }

    const bool was_running = m_backend && m_backend->status().initialized;
    stopRenderer();
    m_kind = kind;
    if (was_running || isVisible())
        return startRenderer();

    publishStatus(tr("Selected"));
    return true;
}

bool RPCS3RenderWidget::startRenderer()
{
    stopRenderer();
    m_backend = create_renderer_backend(m_kind);
    if (!m_backend)
    {
        m_lastError = tr("Unable to create %1.").arg(QString::fromUtf8(renderer_backend_name(m_kind)));
        publishStatus();
        return false;
    }

    std::string error;
    const bool initialized = m_backend->initialize(surfaceConfig(), error);
    if (!initialized)
    {
        m_lastError = QString::fromStdString(error);
        publishStatus();
        return false;
    }

    m_lastError.clear();
    m_elapsed.restart();
    m_frameTimer.start();
    publishStatus(tr("Ready"));
    return true;
}

void RPCS3RenderWidget::stopRenderer()
{
    m_frameTimer.stop();
    if (m_backend)
        m_backend->shutdown();
    m_backend.reset();
}

QString RPCS3RenderWidget::statusText() const
{
    if (!m_lastError.isEmpty())
        return m_lastError;
    if (!m_backend)
        return tr("%1 selected; renderer is stopped.").arg(QString::fromUtf8(renderer_backend_name(m_kind)));

    const backend_status current = m_backend->status();
    QString message = QString::fromStdString(current.message);
    if (!current.device_name.empty())
        message += tr(" Device: %1.").arg(QString::fromStdString(current.device_name));
    return message;
}

void RPCS3RenderWidget::showEvent(QShowEvent* event)
{
    QWidget::showEvent(event);
    if (!m_backend || !m_backend->status().initialized)
        startRenderer();
}

void RPCS3RenderWidget::hideEvent(QHideEvent* event)
{
    m_frameTimer.stop();
    QWidget::hideEvent(event);
}

void RPCS3RenderWidget::resizeEvent(QResizeEvent* event)
{
    QWidget::resizeEvent(event);
    if (!m_backend || !m_backend->status().initialized)
        return;

    const auto config = surfaceConfig();
    std::string error;
    if (!m_backend->resize(config.pixel_width, config.pixel_height, config.content_scale, error))
    {
        m_lastError = QString::fromStdString(error);
        publishStatus();
    }
}

void RPCS3RenderWidget::presentFrame()
{
    if (!m_backend || !m_backend->status().initialized)
        return;

    const double seconds = static_cast<double>(m_elapsed.elapsed()) / 1000.0;
    const float red = static_cast<float>(0.12 + 0.08 * (std::sin(seconds * 0.71) + 1.0));
    const float green = static_cast<float>(0.14 + 0.10 * (std::sin(seconds * 0.43 + 1.3) + 1.0));
    const float blue = static_cast<float>(0.24 + 0.18 * (std::sin(seconds * 0.59 + 2.1) + 1.0));

    std::string error;
    if (!m_backend->present_test_frame(red, green, blue, 1.0f, error))
    {
        m_lastError = QString::fromStdString(error);
        m_frameTimer.stop();
        publishStatus();
        return;
    }

    if (m_elapsed.elapsed() < 100)
        publishStatus(tr("Presenting"));
}

rpcs3::ios::render::surface_config RPCS3RenderWidget::surfaceConfig() const
{
    const qreal scale = std::max<qreal>(devicePixelRatioF(), 1.0);
    rpcs3::ios::render::surface_config config;
    config.native_view = reinterpret_cast<void*>(static_cast<quintptr>(winId()));
    config.pixel_width = std::max(1, qRound(width() * scale));
    config.pixel_height = std::max(1, qRound(height() * scale));
    config.content_scale = static_cast<float>(scale);
    config.vsync = true;
    return config;
}

void RPCS3RenderWidget::publishStatus(const QString& prefix)
{
    QString text = statusText();
    if (!prefix.isEmpty())
        text = prefix + QStringLiteral(": ") + text;
    emit rendererStatusChanged(text);
}
