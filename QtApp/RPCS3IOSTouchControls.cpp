#include "RPCS3CoreBridge.h"

#include <QApplication>
#include <QGridLayout>
#include <QPointer>
#include <QPushButton>
#include <QSizePolicy>
#include <QTimer>
#include <QWidget>

#include <atomic>
#include <memory>

namespace
{
QPushButton* makePadButton(
    QWidget* parent,
    const QString& label,
    unsigned int mask,
    const std::shared_ptr<std::atomic_uint>& state)
{
    auto* button = new QPushButton(label, parent);
    button->setObjectName(QStringLiteral("rpcs3IOSPadButton_%1").arg(mask));
    button->setMinimumSize(44, 44);
    button->setMaximumSize(68, 68);
    button->setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Preferred);
    button->setFocusPolicy(Qt::NoFocus);
    button->setAttribute(Qt::WA_AcceptTouchEvents, true);
    button->setStyleSheet(QStringLiteral(
        "QPushButton {"
        " color: white; background: rgba(20, 20, 24, 150);"
        " border: 1px solid rgba(255,255,255,155); border-radius: 22px;"
        " font-size: 17px; font-weight: 600; padding: 2px;"
        "}"
        "QPushButton:pressed { background: rgba(75, 115, 210, 220); }"));

    QObject::connect(button, &QPushButton::pressed, parent, [state, mask]()
    {
        state->fetch_or(mask, std::memory_order_release);
    });
    QObject::connect(button, &QPushButton::released, parent, [state, mask]()
    {
        state->fetch_and(~mask, std::memory_order_release);
    });
    return button;
}

void installTouchControls()
{
    for (QWidget* topLevel : QApplication::topLevelWidgets())
    {
        if (!topLevel)
            continue;

        QWidget* renderHost = topLevel->findChild<QWidget*>(QStringLiteral("rpcs3IOSNativeRenderHost"));
        if (!renderHost || renderHost->property("rpcs3IOSTouchControlsInstalled").toBool())
            continue;

        renderHost->setProperty("rpcs3IOSTouchControlsInstalled", true);
        const auto state = std::make_shared<std::atomic_uint>(0u);

        auto* layout = new QGridLayout(renderHost);
        layout->setContentsMargins(8, 8, 8, 10);
        layout->setHorizontalSpacing(5);
        layout->setVerticalSpacing(5);
        layout->setRowStretch(1, 1);
        layout->setColumnStretch(4, 1);

        auto add = [&](int row, int column, const QString& label, unsigned int mask)
        {
            layout->addWidget(makePadButton(renderHost, label, mask, state), row, column, Qt::AlignCenter);
        };

        add(0, 0, QStringLiteral("L2"), RPCS3IOSCorePadL2);
        add(0, 1, QStringLiteral("L1"), RPCS3IOSCorePadL1);
        add(0, 7, QStringLiteral("R1"), RPCS3IOSCorePadR1);
        add(0, 8, QStringLiteral("R2"), RPCS3IOSCorePadR2);

        add(2, 1, QStringLiteral("↑"), RPCS3IOSCorePadUp);
        add(3, 0, QStringLiteral("←"), RPCS3IOSCorePadLeft);
        add(3, 2, QStringLiteral("→"), RPCS3IOSCorePadRight);
        add(4, 1, QStringLiteral("↓"), RPCS3IOSCorePadDown);

        add(2, 7, QStringLiteral("△"), RPCS3IOSCorePadTriangle);
        add(3, 6, QStringLiteral("□"), RPCS3IOSCorePadSquare);
        add(3, 8, QStringLiteral("○"), RPCS3IOSCorePadCircle);
        add(4, 7, QStringLiteral("×"), RPCS3IOSCorePadCross);

        add(4, 3, QStringLiteral("Select"), RPCS3IOSCorePadSelect);
        add(4, 4, QStringLiteral("PS"), RPCS3IOSCorePadPS);
        add(4, 5, QStringLiteral("Start"), RPCS3IOSCorePadStart);

        auto* pump = new QTimer(renderHost);
        pump->setTimerType(Qt::PreciseTimer);
        pump->setInterval(16);
        QObject::connect(pump, &QTimer::timeout, renderHost, [renderHost, state]()
        {
            const unsigned int buttons = renderHost->isVisible()
                ? state->load(std::memory_order_acquire)
                : 0u;
            (void)rpcs3_ios_core_set_pad_state(buttons, 128, 128, 128, 128);
        });
        pump->start();

        QObject::connect(renderHost, &QObject::destroyed, qApp, [state]()
        {
            state->store(0u, std::memory_order_release);
            (void)rpcs3_ios_core_set_pad_state(0u, 128, 128, 128, 128);
        });
    }
}

void scheduleTouchControls()
{
    QTimer::singleShot(0, qApp, []()
    {
        installTouchControls();
        QTimer::singleShot(250, qApp, installTouchControls);
    });
}
} // namespace

Q_COREAPP_STARTUP_FUNCTION(scheduleTouchControls)
