#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(path: Path, needle: str, replacement: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"Unable to locate upstream {label} block in {path}")
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def patch_fatal_error_relaunch(upstream_root: Path) -> None:
    """Keep the desktop relaunch behavior while avoiding process creation on iOS."""

    source = upstream_root / "rpcs3/rpcs3.cpp"
    marker = "RPCS3 iOS: an app bundle cannot relaunch itself as a child process"
    text = source.read_text(encoding="utf-8")
    if marker in text:
        return

    needle = '''#ifdef _WIN32
		constexpr DWORD size = 32767;
		std::vector<wchar_t> buffer(size);
		GetModuleFileNameW(nullptr, buffer.data(), size);
		const std::wstring arg(text.cbegin(), text.cend()); // ignore unicode for now
		_wspawnl(_P_WAIT, buffer.data(), buffer.data(), L"--error", arg.c_str(), nullptr);
#else
		pid_t pid;
		std::vector<char> data(text.data(), text.data() + text.size() + 1);
		std::string run_arg = +s_argv0;
		std::string err_arg = "--error";

		if (run_arg.find_first_of('/') == umax)
		{
			// AppImage has "rpcs3" in argv[0], can't just execute it
#ifdef __linux__
			char buffer[PATH_MAX]{};
			if (::readlink("/proc/self/exe", buffer, sizeof(buffer) - 1) > 0)
			{
				printf("Found exec link: %s\n", buffer);
				run_arg = buffer;
			}
#endif
		}

		char* argv[] = {run_arg.data(), err_arg.data(), data.data(), nullptr};
		int ret = posix_spawn(&pid, run_arg.c_str(), nullptr, nullptr, argv, environ);

		if (ret == 0)
		{
			int status;
			waitpid(pid, &status, 0);
		}
		else
		{
			std::fprintf(stderr, "posix_spawn() failed: %d\n", ret);
		}
#endif
'''

    replacement = '''#if defined(RPCS3_IOS)
		// RPCS3 iOS: an app bundle cannot relaunch itself as a child process.
		// Display the same upstream fatal dialog in-process and then abort below.
		show_report(text);
#elif defined(_WIN32)
		constexpr DWORD size = 32767;
		std::vector<wchar_t> buffer(size);
		GetModuleFileNameW(nullptr, buffer.data(), size);
		const std::wstring arg(text.cbegin(), text.cend()); // ignore unicode for now
		_wspawnl(_P_WAIT, buffer.data(), buffer.data(), L"--error", arg.c_str(), nullptr);
#else
		pid_t pid;
		std::vector<char> data(text.data(), text.data() + text.size() + 1);
		std::string run_arg = +s_argv0;
		std::string err_arg = "--error";

		if (run_arg.find_first_of('/') == umax)
		{
			// AppImage has "rpcs3" in argv[0], can't just execute it
#ifdef __linux__
			char buffer[PATH_MAX]{};
			if (::readlink("/proc/self/exe", buffer, sizeof(buffer) - 1) > 0)
			{
				printf("Found exec link: %s\n", buffer);
				run_arg = buffer;
			}
#endif
		}

		char* argv[] = {run_arg.data(), err_arg.data(), data.data(), nullptr};
		int ret = posix_spawn(&pid, run_arg.c_str(), nullptr, nullptr, argv, environ);

		if (ret == 0)
		{
			int status;
			waitpid(pid, &status, 0);
		}
		else
		{
			std::fprintf(stderr, "posix_spawn() failed: %d\n", ret);
		}
#endif
'''

    if needle not in text:
        raise SystemExit("Unable to locate upstream fatal-error process relaunch block")
    source.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    patch_fatal_error_relaunch(args.upstream_root)
    print("Patched the full RPCS3 Qt frontend to keep fatal errors in-process on iOS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
