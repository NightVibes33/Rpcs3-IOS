#include "RPCS3RendererIntegration.h"
#include "RPCS3RenderWidget.h"

#include <QAction>
#include <QActionGroup>
#include <QMainWindow>
#include <QMenu>
#include <QMenuBar>
#include <QStatusBar>
#include <QVariant>
#include <QVBoxLayout>

using rpcs3::ios::render::backend_kind;
using rpcs3::ios::render::renderer_backend_compiled;

void RPCS3InstallRendererIntegration(QMainWindow* window)
{
    if (!window || !window->centralWidget())
        return;

    auto* surface = new RPCS3RenderWidget(window->centralWidget());
    surface->hide();

    if (auto* layout = qobject_cast<QVBoxLayout*>(window->centralWidget()->layout()))
        layout->insertWidget(1, surface, 1);
    else
        surface->setParent(window->centralWidget());

    QMenu* configuration = window->findChild<QMenu*>(QStringLiteral("menuConfiguration"));
    if (!configuration)
        configuration = window->menuBar()->addMenu(QObject::tr("Configuration"));

    QMenu* renderer_menu = configuration->addMenu(QObject::tr("Renderer"));
    renderer_menu->setObjectName(QStringLiteral("menuIOSRenderer"));

    auto* backend_group = new QActionGroup(renderer_menu);
    backend_group->setExclusive(true);

    QAction* vulkan = renderer_menu->addAction(QObject::tr("Vulkan (MoltenVK)"));
    vulkan->setObjectName(QStringLiteral("rendererVulkanAct"));
    vulkan->setCheckable(true);
    vulkan->setEnabled(renderer_backend_compiled(backend_kind::vulkan));
    backend_group->addAction(vulkan);

    QAction* metal = renderer_menu->addAction(QObject::tr("Metal"));
    metal->setObjectName(QStringLiteral("rendererMetalAct"));
    metal->setCheckable(true);
    metal->setEnabled(renderer_backend_compiled(backend_kind::metal));
    backend_group->addAction(metal);

    if (surface->backendKind() == backend_kind::vulkan && vulkan->isEnabled())
        vulkan->setChecked(true);
    else
        metal->setChecked(true);

    renderer_menu->addSeparator();
    QAction* show_surface = renderer_menu->addAction(QObject::tr("Show Renderer Surface"));
    show_surface->setObjectName(QStringLiteral("rendererSurfaceAct"));
    show_surface->setCheckable(true);

    QAction* self_test = renderer_menu->addAction(QObject::tr("Run GPU Self-Test"));
    self_test->setObjectName(QStringLiteral("rendererSelfTestAct"));

    QObject::connect(vulkan, &QAction::triggered, surface, [surface, show_surface]()
    {
        if (surface->setBackend(backend_kind::vulkan))
        {
            show_surface->setChecked(true);
            surface->show();
        }
    });
    QObject::connect(metal, &QAction::triggered, surface, [surface, show_surface]()
    {
        if (surface->setBackend(backend_kind::metal))
        {
            show_surface->setChecked(true);
            surface->show();
        }
    });
    QObject::connect(show_surface, &QAction::toggled, surface, [surface](bool visible)
    {
        surface->setVisible(visible);
        if (visible)
            surface->startRenderer();
        else
            surface->stopRenderer();
    });
    QObject::connect(self_test, &QAction::triggered, surface, [surface, show_surface]()
    {
        show_surface->setChecked(true);
        surface->show();
        surface->startRenderer();
    });
    QObject::connect(surface, &RPCS3RenderWidget::rendererStatusChanged,
                     window, [window](const QString& status)
    {
        if (window->statusBar())
            window->statusBar()->showMessage(status, 8000);
    });

    window->setProperty("RPCS3RendererSurface", QVariant::fromValue<QObject*>(surface));
}
