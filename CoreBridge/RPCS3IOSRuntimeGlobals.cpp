#include <string>

// The desktop Qt executable owns this command-line override in rpcs3.cpp.
// The standalone iOS runtime framework excludes that executable but still
// links pad_config.cpp, which reads the same global while resolving profiles.
std::string g_input_config_override;
