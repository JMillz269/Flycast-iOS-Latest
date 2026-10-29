// Diagnostics for the iOS debug IPA (FLYCAST_DIAG): breadcrumbs + crash reporting.
#pragma once

#include "Log.h"

#ifdef FLYCAST_DIAG

// Installs signal handlers (SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE), a std::terminate handler,
// and tees stderr (where MoltenVK writes its own log) to <dir>/mvk-stderr.log.
// The crash report goes to <dir>/flycast-crash.txt. Must be called before os_InstallFaultHandler() so that
// Flycast's own SIGSEGV handler chains to this one for faults it doesn't handle.
void crashdiag_install(const char *dir);

// Remembers the last step reached; printed in the crash report. Not thread safe on purpose (async-signal safe reads).
void crashdiag_breadcrumb(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

// Log a step both as a NOTICE log line and as the crash breadcrumb.
#define DIAG_STEP(t, ...)                                                                          \
		do {                                                                                       \
			crashdiag_breadcrumb(__VA_ARGS__);                                                     \
			NOTICE_LOG(t, __VA_ARGS__);                                                            \
		} while (0)

// Same as NOTICE_LOG, only compiled in diag builds
#define DIAG_LOG(t, ...) NOTICE_LOG(t, __VA_ARGS__)

#else

#define DIAG_STEP(t, ...) do {} while (0)
#define DIAG_LOG(t, ...) do {} while (0)

#endif
