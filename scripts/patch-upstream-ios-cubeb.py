#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, description: str) -> str:
    if old not in text:
        raise SystemExit(f"Unable to locate Cubeb region: {description}")
    return text.replace(old, new, 1)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Keep Cubeb's AudioUnit stream backend while excluding macOS-only CoreAudio device APIs on iOS"
    )
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    source = args.upstream_root / "3rdparty/cubeb/cubeb/src/cubeb_audiounit.cpp"
    text = source.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "using namespace std;\n\n",
        """using namespace std;

#if TARGET_OS_IPHONE
// AudioUnit is available to iOS applications, but the desktop CoreAudio
// AudioObject device-enumeration types are not. Cubeb's iOS stream path uses
// integer device placeholders and the current route selected by iOS.
typedef UInt32 AudioDeviceID;
typedef UInt32 AudioObjectID;
#ifndef kAudioObjectUnknown
#define kAudioObjectUnknown 0
#endif
#define AudioGetCurrentHostTime mach_absolute_time
#endif

""",
        "early iOS AudioUnit type aliases",
    )

    property_addresses = """const AudioObjectPropertyAddress DEFAULT_INPUT_DEVICE_PROPERTY_ADDRESS = {
    kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal,
    kAudioObjectPropertyElementMaster};

const AudioObjectPropertyAddress DEFAULT_OUTPUT_DEVICE_PROPERTY_ADDRESS = {
    kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal,
    kAudioObjectPropertyElementMaster};

const AudioObjectPropertyAddress DEVICE_IS_ALIVE_PROPERTY_ADDRESS = {
    kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal,
    kAudioObjectPropertyElementMaster};

const AudioObjectPropertyAddress DEVICES_PROPERTY_ADDRESS = {
    kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
    kAudioObjectPropertyElementMaster};

const AudioObjectPropertyAddress INPUT_DATA_SOURCE_PROPERTY_ADDRESS = {
    kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeInput,
    kAudioObjectPropertyElementMaster};

const AudioObjectPropertyAddress OUTPUT_DATA_SOURCE_PROPERTY_ADDRESS = {
    kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput,
    kAudioObjectPropertyElementMaster};
"""
    text = replace_once(
        text,
        property_addresses,
        "#if !TARGET_OS_IPHONE\n" + property_addresses + "#endif\n",
        "desktop CoreAudio property addresses",
    )

    device_declarations = """static vector<AudioObjectID>
audiounit_get_devices_of_type(cubeb_device_type devtype);
static UInt32
audiounit_get_device_presentation_latency(AudioObjectID devid,
                                          AudioObjectPropertyScope scope);
"""
    text = replace_once(
        text,
        device_declarations,
        "#if !TARGET_OS_IPHONE\n" + device_declarations + "#endif\n",
        "desktop device-query declarations",
    )

    listener_struct = """struct property_listener {
  AudioDeviceID device_id;
  const AudioObjectPropertyAddress * property_address;
  AudioObjectPropertyListenerProc callback;
  cubeb_stream * stream;

  property_listener(AudioDeviceID id,
                    const AudioObjectPropertyAddress * address,
                    AudioObjectPropertyListenerProc proc, cubeb_stream * stm)
      : device_id(id), property_address(address), callback(proc), stream(stm)
  {
  }
};
"""
    text = replace_once(
        text,
        listener_struct,
        "#if !TARGET_OS_IPHONE\n" + listener_struct + "#endif\n",
        "desktop property-listener structure",
    )

    listener_fields = """  /* Listeners indicating what system events are monitored. */
  unique_ptr<property_listener> default_input_listener;
  unique_ptr<property_listener> default_output_listener;
  unique_ptr<property_listener> input_alive_listener;
  unique_ptr<property_listener> input_source_listener;
  unique_ptr<property_listener> output_source_listener;
"""
    text = replace_once(
        text,
        listener_fields,
        "#if !TARGET_OS_IPHONE\n" + listener_fields + "#endif\n",
        "desktop listener storage",
    )

    late_aliases = """#if TARGET_OS_IPHONE
typedef UInt32 AudioDeviceID;
typedef UInt32 AudioObjectID;

#define AudioGetCurrentHostTime mach_absolute_time

#endif

"""
    text = replace_once(text, late_aliases, "", "late duplicate iOS aliases")

    text = replace_once(
        text,
        "      audiounit_reinit_stream_async(stm, DEV_INPUT | DEV_OUTPUT);",
        """#if !TARGET_OS_IPHONE
      audiounit_reinit_stream_async(stm, DEV_INPUT | DEV_OUTPUT);
#else
      // iOS owns route changes through AVAudioSession. Stop this stream instead
      // of invoking Cubeb's macOS AudioObject listener/reopen machinery.
      stm->shutdown = true;
#endif""",
        "desktop asynchronous stream reinitialization call",
    )

    required = (
        "#if TARGET_OS_IPHONE\n// AudioUnit is available",
        "#if !TARGET_OS_IPHONE\nconst AudioObjectPropertyAddress",
        "#if !TARGET_OS_IPHONE\nstruct property_listener",
        "iOS owns route changes through AVAudioSession",
    )
    for marker in required:
        if marker not in text:
            raise SystemExit(f"Cubeb iOS patch verification failed: {marker}")

    source.write_text(text, encoding="utf-8")
    print(f"Patched Cubeb AudioUnit iOS guards in {source}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
