// Diagnostics for the iOS debug IPA (FLYCAST_DIAG): breadcrumbs + crash reporting.
#ifdef FLYCAST_DIAG

#include "CrashDiag.h"

#include <cerrno>
#include <csignal>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <execinfo.h>
#include <sys/ucontext.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

namespace
{
constexpr int NumSignals = 6;
const int signals[NumSignals] = { SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE };

struct sigaction previous[NumSignals];
char crashPath[1024];
char breadcrumb[256] = "(none)";
volatile sig_atomic_t inHandler = 0;
int crashFd = -1;
std::terminate_handler previousTerminate;

// ---- async-signal-safe helpers ----
void wr(const char *s)
{
	if (crashFd >= 0)
		(void)!write(crashFd, s, strlen(s));
	(void)!write(STDERR_FILENO, s, strlen(s));
}

void wrHex(const char *label, uint64_t v)
{
	char buf[64];
	int n = 0;
	buf[n++] = '0';
	buf[n++] = 'x';
	bool started = false;
	for (int shift = 60; shift >= 0; shift -= 4)
	{
		int d = (v >> shift) & 0xf;
		if (d != 0 || started || shift == 0)
		{
			buf[n++] = "0123456789abcdef"[d];
			started = true;
		}
	}
	buf[n++] = '\n';
	buf[n] = 0;
	wr(label);
	wr(buf);
}

void wrInt(const char *label, long v)
{
	char buf[32];
	snprintf(buf, sizeof(buf), "%ld\n", v);
	wr(label);
	wr(buf);
}

const char *sigName(int sig)
{
	switch (sig)
	{
	case SIGSEGV: return "SIGSEGV";
	case SIGBUS: return "SIGBUS";
	case SIGILL: return "SIGILL";
	case SIGABRT: return "SIGABRT";
	case SIGTRAP: return "SIGTRAP";
	case SIGFPE: return "SIGFPE";
	default: return "?";
	}
}

void dumpBacktrace(uint64_t pc, uint64_t lr, uint64_t fp, uint64_t sp)
{
	void *frames[64];
	int n = 0;
	frames[n++] = (void *)pc;
	if (lr != 0)
		frames[n++] = (void *)lr;
	// Frame pointer walk (arm64 frame record: [fp] = previous fp, [fp + 8] = return address)
	uint64_t cur = fp;
	while (n < 64 && cur != 0 && (cur & 0xf) == 0 && cur > sp && cur - sp < (64u << 20))
	{
		uint64_t *rec = (uint64_t *)cur;
		uint64_t next = rec[0];
		uint64_t ret = rec[1];
		if (ret == 0)
			break;
		frames[n++] = (void *)ret;
		if (next <= cur)
			break;
		cur = next;
	}
	wr("Backtrace (frame pointer walk):\n");
	if (crashFd >= 0)
		backtrace_symbols_fd(frames, n, crashFd);
	backtrace_symbols_fd(frames, n, STDERR_FILENO);
}

void writeHeader(const char *what)
{
	wr("\n===== FLYCAST CRASH REPORT =====\n");
	wr(what);
	wr("\nLast breadcrumb: ");
	wr(breadcrumb);
	wr("\n");
#ifdef __APPLE__
	wrHex("Image[0] slide: ", (uint64_t)_dyld_get_image_vmaddr_slide(0));
	wr("Image[0] name: ");
	wr(_dyld_get_image_name(0));
	wr("\n");
#endif
	char name[64] = "";
	pthread_getname_np(pthread_self(), name, sizeof(name));
	wr("Thread: ");
	wr(name);
	wrHex(" id=", (uint64_t)(uintptr_t)pthread_self());
}

void crashHandler(int sig, siginfo_t *si, void *ctx)
{
	int idx = 0;
	for (int i = 0; i < NumSignals; i++)
		if (signals[i] == sig)
			idx = i;
	if (inHandler)
	{
		// crash inside the crash handler: give up
		signal(sig, SIG_DFL);
		raise(sig);
		return;
	}
	inHandler = 1;

	writeHeader(sigName(sig));
	wrInt("si_code: ", si != nullptr ? si->si_code : -1);
	wrHex("fault address (si_addr): ", si != nullptr ? (uint64_t)(uintptr_t)si->si_addr : 0);
#if defined(__APPLE__) && defined(__arm64__)
	ucontext_t *uc = (ucontext_t *)ctx;
	if (uc != nullptr && uc->uc_mcontext != nullptr)
	{
		_STRUCT_ARM_THREAD_STATE64 *ss = &uc->uc_mcontext->__ss;
		uint64_t pc = __darwin_arm_thread_state64_get_pc(*ss);
		uint64_t lr = __darwin_arm_thread_state64_get_lr(*ss);
		uint64_t fp = __darwin_arm_thread_state64_get_fp(*ss);
		uint64_t sp = __darwin_arm_thread_state64_get_sp(*ss);
		wrHex("pc: ", pc);
		wrHex("lr: ", lr);
		wrHex("sp: ", sp);
		wrHex("fp: ", fp);
		wrHex("esr: ", uc->uc_mcontext->__es.__esr);
		wrHex("far: ", uc->uc_mcontext->__es.__far);
		for (int i = 0; i < 29; i++)
		{
			char label[8];
			snprintf(label, sizeof(label), "x%d: ", i);
			wrHex(label, ss->__x[i]);
		}
		dumpBacktrace(pc, lr, fp, sp);
	}
#else
	(void)ctx;
#endif
	wr("===== END OF CRASH REPORT =====\n");
	if (crashFd >= 0)
		fsync(crashFd);

	inHandler = 0;
	// Hand over to whoever was installed before us (or the default action)
	const struct sigaction& prev = previous[idx];
	if ((prev.sa_flags & SA_SIGINFO) && prev.sa_sigaction != nullptr)
	{
		prev.sa_sigaction(sig, si, ctx);
		return;
	}
	if (!(prev.sa_flags & SA_SIGINFO) && prev.sa_handler != SIG_DFL && prev.sa_handler != SIG_IGN && prev.sa_handler != nullptr)
	{
		prev.sa_handler(sig);
		return;
	}
	signal(sig, SIG_DFL);
	if (sig == SIGABRT || sig == SIGTRAP)
		raise(sig);
	// for synchronous faults, returning re-executes the faulting instruction with the default action
}

void terminateHandler()
{
	std::string what = "std::terminate called";
	try {
		std::exception_ptr ep = std::current_exception();
		if (ep)
			std::rethrow_exception(ep);
		what += " (no active exception)";
	} catch (const std::exception& e) {
		what += " - uncaught exception: ";
		what += e.what();
	} catch (...) {
		what += " - uncaught exception of unknown type";
	}
	ERROR_LOG(COMMON, "%s", what.c_str());
	writeHeader(what.c_str());
	void *frames[64];
	int n = backtrace(frames, 64);
	if (crashFd >= 0)
		backtrace_symbols_fd(frames, n, crashFd);
	backtrace_symbols_fd(frames, n, STDERR_FILENO);
	wr("===== END OF CRASH REPORT =====\n");
	if (crashFd >= 0)
		fsync(crashFd);
	if (previousTerminate != nullptr)
		previousTerminate();
	abort();
}

// stderr tee: MoltenVK (and NSLog) write to stderr. Keep the original destination (LiveContainer's log viewer, Xcode...)
// and also copy everything to a file.
int teeSavedFd = -1;
int teeFileFd = -1;
int teePipe[2] = { -1, -1 };

void *teeThread(void *)
{
#ifdef __APPLE__
	pthread_setname_np("diag-stderr-tee");
#endif
	char buf[4096];
	for (;;)
	{
		ssize_t n = read(teePipe[0], buf, sizeof(buf));
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			break;
		if (teeSavedFd >= 0)
			(void)!write(teeSavedFd, buf, n);
		if (teeFileFd >= 0)
			(void)!write(teeFileFd, buf, n);
	}
	return nullptr;
}

void startStderrTee(const std::string& dir)
{
	std::string path = dir + "/mvk-stderr.log";
	std::string prev = dir + "/mvk-stderr.prev.log";
	rename(path.c_str(), prev.c_str());
	teeFileFd = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (teeFileFd < 0 || pipe(teePipe) != 0)
		return;
	teeSavedFd = dup(STDERR_FILENO);
	dup2(teePipe[1], STDERR_FILENO);
	setvbuf(stderr, nullptr, _IONBF, 0);
	pthread_t th;
	pthread_create(&th, nullptr, teeThread, nullptr);
	pthread_detach(th);
}
}

void crashdiag_breadcrumb(const char *fmt, ...)
{
	char tmp[sizeof(breadcrumb)];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(tmp, sizeof(tmp), fmt, ap);
	va_end(ap);
	memcpy(breadcrumb, tmp, sizeof(breadcrumb));
}

void crashdiag_install(const char *dir)
{
	static bool installed = false;
	if (installed)
		return;
	installed = true;

	std::string d(dir);
	while (d.size() > 1 && d.back() == '/')
		d.pop_back();

	std::string path = d + "/flycast-crash.txt";
	std::string prev = d + "/flycast-crash.prev.txt";
	rename(path.c_str(), prev.c_str());
	snprintf(crashPath, sizeof(crashPath), "%s", path.c_str());
	crashFd = open(crashPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);

	startStderrTee(d);

	// alternate stack so stack overflows can be reported too
	static char altStack[64 * 1024];
	stack_t ss;
	ss.ss_sp = altStack;
	ss.ss_size = sizeof(altStack);
	ss.ss_flags = 0;
	sigaltstack(&ss, nullptr);

	for (int i = 0; i < NumSignals; i++)
	{
		struct sigaction act;
		memset(&act, 0, sizeof(act));
		act.sa_sigaction = crashHandler;
		sigemptyset(&act.sa_mask);
		act.sa_flags = SA_SIGINFO | SA_ONSTACK;
		sigaction(signals[i], &act, &previous[i]);
	}
	previousTerminate = std::set_terminate(terminateHandler);

	NOTICE_LOG(COMMON, "Crash diagnostics installed, crash report: %s", crashPath);
}

#endif // FLYCAST_DIAG
