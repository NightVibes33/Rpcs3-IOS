#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    cmake = args.upstream_root / "3rdparty/OpenAL/openal-soft/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    marker = "RPCS3 iOS: Apple platforms provide atomics without libatomic"
    if marker in text:
        print(f"OpenAL iOS atomic compatibility already applied: {cmake}")
        return 0

    old = '''# Some systems may need libatomic for atomic functions to work
set(OLD_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES})
set(CMAKE_REQUIRED_LIBRARIES ${OLD_REQUIRED_LIBRARIES} atomic)
check_cxx_source_compiles("#include <atomic>
std::atomic<int> foo{0};
int main() { return foo.fetch_add(2); }"
HAVE_LIBATOMIC)
if(NOT HAVE_LIBATOMIC)
    set(CMAKE_REQUIRED_LIBRARIES "${OLD_REQUIRED_LIBRARIES}")
else()
    set(EXTRA_LIBS atomic ${EXTRA_LIBS})
endif()
unset(OLD_REQUIRED_LIBRARIES)
'''
    new = '''# Some systems may need libatomic for atomic functions to work.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # RPCS3 iOS: Apple platforms provide atomics without libatomic. The iOS SDK
    # intentionally has no libatomic, while cross try_compile can incorrectly
    # report success by seeing a host library and leak -latomic into device links.
    set(HAVE_LIBATOMIC FALSE CACHE INTERNAL "iOS uses compiler/runtime atomics" FORCE)
else()
    set(OLD_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES})
    set(CMAKE_REQUIRED_LIBRARIES ${OLD_REQUIRED_LIBRARIES} atomic)
    check_cxx_source_compiles("#include <atomic>
std::atomic<int> foo{0};
int main() { return foo.fetch_add(2); }"
    HAVE_LIBATOMIC)
    if(NOT HAVE_LIBATOMIC)
        set(CMAKE_REQUIRED_LIBRARIES "${OLD_REQUIRED_LIBRARIES}")
    else()
        set(EXTRA_LIBS atomic ${EXTRA_LIBS})
    endif()
    unset(OLD_REQUIRED_LIBRARIES)
endif()
'''

    if old not in text:
        raise SystemExit(f"Unable to locate OpenAL libatomic probe in {cmake}")

    cmake.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"Disabled OpenAL's host libatomic probe for the physical iOS target: {cmake}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
