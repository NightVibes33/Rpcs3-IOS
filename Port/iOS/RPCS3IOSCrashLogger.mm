#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <exception>

// QtCore's static iOS package still references desktop IOKit registry helpers.
// iOS applications cannot rely on that private framework being loadable, so
// satisfy those optional hardware queries locally and report no matching
// desktop services.
extern "C" CFMutableDictionaryRef IOServiceMatching(const char*)
{
    return nullptr;
}

extern "C" uint32_t IOServiceGetMatchingService(uint32_t, CFDictionaryRef matching)
{
    if (matching)
        CFRelease(matching);
    return 0;
}

extern "C" CFTypeRef IORegistryEntryCreateCFProperty(
    uint32_t, CFStringRef, CFAllocatorRef, uint32_t)
{
    return nullptr;
}

namespace
{
int g_log_fd = STDERR_FILENO;
volatile sig_atomic_t g_handling_signal = 0;

void writeText(const char* text)
{
    if (text)
        write(g_log_fd, text, strlen(text));
}

void writeTimestamp()
{
    char timestamp[64] = {};
    const time_t now = time(nullptr);
    struct tm local = {};
    localtime_r(&now, &local);
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S %z", &local);
    dprintf(g_log_fd, "\n[%s] ", timestamp);
}

void writeBacktrace()
{
    void* frames[64] = {};
    const int count = backtrace(frames, 64);
    dprintf(g_log_fd, "Native backtrace (%d frames):\n", count);
    backtrace_symbols_fd(frames, count, g_log_fd);
}

void handleSignal(int signalNumber, siginfo_t* info, void*)
{
    if (g_handling_signal)
        _exit(128 + signalNumber);
    g_handling_signal = 1;

    writeTimestamp();
    dprintf(g_log_fd, "FATAL SIGNAL %d (%s), code=%d, address=%p\n",
            signalNumber, strsignal(signalNumber), info ? info->si_code : 0,
            info ? info->si_addr : nullptr);
    writeBacktrace();
    fsync(g_log_fd);

    signal(signalNumber, SIG_DFL);
    raise(signalNumber);
}

void handleObjectiveCException(NSException* exception)
{
    writeTimestamp();
    dprintf(g_log_fd, "UNCAUGHT OBJECTIVE-C EXCEPTION: %s\nReason: %s\n",
            exception.name.UTF8String, exception.reason.UTF8String);
    for (NSString* symbol in exception.callStackSymbols)
        dprintf(g_log_fd, "%s\n", symbol.UTF8String);
    fsync(g_log_fd);
}

[[noreturn]] void handleTerminate()
{
    writeTimestamp();
    writeText("C++ std::terminate invoked\n");
    writeBacktrace();
    fsync(g_log_fd);
    abort();
}

void installSignalHandler(int signalNumber)
{
    struct sigaction action = {};
    action.sa_sigaction = handleSignal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_SIGINFO | SA_RESETHAND;
    sigaction(signalNumber, &action, nullptr);
}
}

extern "C" void rpcs3_ios_debug_log(const char* message)
{
    writeTimestamp();
    dprintf(g_log_fd, "%s\n", message ? message : "(null)");
    fsync(g_log_fd);
}

__attribute__((constructor))
static void installRPCS3IOSCrashLogger()
{
    @autoreleasepool
    {
        NSString* documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:documents
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSString* path = [documents stringByAppendingPathComponent:@"RPCS3-debug.log"];
        const int fd = open(path.fileSystemRepresentation, O_CREAT | O_WRONLY | O_APPEND, 0644);
        if (fd >= 0)
        {
            g_log_fd = fd;
            dup2(fd, STDOUT_FILENO);
            dup2(fd, STDERR_FILENO);
        }

        rpcs3_ios_debug_log("RPCS3 process loaded; installing crash handlers");
        dprintf(g_log_fd, "Log path: %s\n", path.fileSystemRepresentation);
        dprintf(g_log_fd, "Process: %s (pid %d)\n", getprogname(), getpid());
        dprintf(g_log_fd, "System: %s %s\n",
                UIDevice.currentDevice.systemName.UTF8String,
                UIDevice.currentDevice.systemVersion.UTF8String);

        NSSetUncaughtExceptionHandler(handleObjectiveCException);
        std::set_terminate(handleTerminate);
        installSignalHandler(SIGABRT);
        installSignalHandler(SIGBUS);
        installSignalHandler(SIGFPE);
        installSignalHandler(SIGILL);
        installSignalHandler(SIGSEGV);
        installSignalHandler(SIGTRAP);
        fsync(g_log_fd);
    }
}
