#include "RPCS3CoreBridge.h"
#include "RPCS3UpstreamRuntimeBridge.h"

extern "C" int rpcs3_ios_core_set_pad_state(
    unsigned int buttons,
    unsigned char left_x,
    unsigned char left_y,
    unsigned char right_x,
    unsigned char right_y)
{
    return rpcs3_ios_upstream_set_pad_state(buttons, left_x, left_y, right_x, right_y);
}
