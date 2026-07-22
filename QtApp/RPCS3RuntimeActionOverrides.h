#pragma once

#include <utility>

class QMainWindow;

/* Replaces the remaining staging-only upstream QActions with real core calls. */
void RPCS3InstallRuntimeActionOverrides(QMainWindow* window);
