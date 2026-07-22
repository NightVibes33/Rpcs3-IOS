#include "RPCS3QtMainWindow.h"
#include "RPCS3RendererIntegration.h"
#include "RPCS3CoreBridge.h"

#include <QApplication>
#include <QCoreApplication>
#include <QMessageBox>
#include <QTimer>

#ifndef RPCS3_QT_BUILD_MARKER
#define RPCS3_QT_BUILD_MARKER "RPCS3 Qt iOS upstream main_window.ui"
#endif

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
    RPCS3InstallRendererIntegration(&window);
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
