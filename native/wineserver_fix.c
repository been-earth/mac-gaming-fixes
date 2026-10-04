// wineserver_fix.c — injected into wineserver (DYLD_INSERT_LIBRARIES; the wrapper script
// is written by Sources/MGFCore/Fixes.swift). Two fixes.
//
// 1. Registry save stall. wineserver is single-threaded. Every 30 s it rewrites each registry
//    branch that changed since the last save, as one text file, from that one thread. With a 12 MB
//    system.reg this takes ~240 ms, during which no process in the bottle gets a server reply or a
//    socket event: a game sees 15 network ticks arrive in one burst. Steam dirties HKLM about once
//    a minute.
//    Fix: while the server is busy (a game is running), make the *periodic* save of a big branch
//    fail fast. The branch stays dirty, so wineserver retries 30 s later and the save goes through
//    once the bottle is quiet. Saves on server exit and of small branches (user.reg) are untouched.
//
// 2. Wi-Fi hold-off. The Mac's Wi-Fi chip holds packets for up to ~25 ms unless some socket on the
//    interface carries a real-time service class, and Wine never sets one. Wine creates every
//    Windows socket inside wineserver, so tagging UDP sockets here covers all games in the bottle.
//    Measured on a 64 Hz flow to the router: best effort median 8.7 ms with 25 % of packets over
//    15 ms; interactive video 3.8 ms with 1.2 %. "Responsive data" (8) does not help.
//
// env: REGSAVE_BUSY_CPU  server CPU share above which big saves are deferred (default 0.05,
//                        0 = never defer)
//      REGSAVE_LOG       file to append one line per registry decision to
//      UDP_SERVICE_TYPE  SO_NET_SERVICE_TYPE for UDP sockets (default 3 = interactive video,
//                        4 = voice, 0 = leave sockets alone)
//
// build: make payload
#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define BIG_BRANCH (1 << 20)  // bytes; anything smaller saves in a few ms

// ponytail: "busy" = wineserver's own CPU share since the previous attempt. Naive but needs no
// knowledge of what runs in the bottle; ~0.17 with Deadlock, calibrate via REGSAVE_LOG if a
// light game slips under it.
static double busy_cpu = 0.05;
static int log_fd = -1;
static char branch[64];  // big *.reg that save_branch() is about to replace, "" if none
static int udp_service = NET_SERVICE_TYPE_VI;

__attribute__((constructor)) static void init(void) {
    const char *s = getenv("REGSAVE_BUSY_CPU");
    if (s) busy_cpu = atof(s);
    if ((s = getenv("UDP_SERVICE_TYPE"))) udp_service = atoi(s);
    if ((s = getenv("REGSAVE_LOG"))) log_fd = open(s, O_WRONLY | O_CREAT | O_APPEND, 0644);
}

static double cpu_share(void) {
    static double last_cpu, last_wall;
    struct rusage ru;
    struct timespec ts;
    getrusage(RUSAGE_SELF, &ru);
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double cpu = ru.ru_utime.tv_sec + ru.ru_stime.tv_sec + (ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1e6;
    double wall = ts.tv_sec + ts.tv_nsec / 1e9;
    double share = (cpu - last_cpu) / (wall - last_wall);
    last_cpu = cpu;
    last_wall = wall;
    return share;
}

// The periodic save and the save on exit reach open() through different callers. The periodic
// one comes back every 30 s, so a call path we have seen before is the periodic one; the first
// save from any path always goes through. Returns 0 when the stack can't be walked.
static int seen_before(void **bt, int depth) {
    static uintptr_t seen[8];
    static int n;
    if (depth < 4) return 0;
    uintptr_t key = (uintptr_t)bt[1] ^ (uintptr_t)bt[2] << 1 ^ (uintptr_t)bt[3] << 2;
    for (int i = 0; i < n; i++)
        if (seen[i] == key) return 1;
    if (n < 8) seen[n++] = key;
    return 0;
}

static int has_suffix(const char *s, const char *suffix) {
    size_t n = strlen(s), m = strlen(suffix);
    return n > m && !strcmp(s + n - m, suffix);
}

static int my_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;

    // save_branch(): open(path, O_WRONLY) to test the file, then open("reg<pid><n>.tmp", O_CREAT|O_EXCL)
    if (flags == O_WRONLY && has_suffix(base, ".reg")) {
        struct stat st;
        branch[0] = 0;
        if (!stat(path, &st) && st.st_size >= BIG_BRANCH) strlcpy(branch, base, sizeof branch);
    } else if ((flags & O_EXCL) && !strncmp(base, "reg", 3) && has_suffix(base, ".tmp")) {
        void *bt[4];
        int periodic = seen_before(bt, backtrace(bt, 4));
        if (branch[0] && periodic) {
            double share = cpu_share();
            int defer = busy_cpu > 0 && share > busy_cpu;
            if (log_fd >= 0) dprintf(log_fd, "%ld %s %s cpu=%.3f\n", (long)time(NULL), defer ? "defer" : "save", branch, share);
            if (defer) {
                branch[0] = 0;
                errno = EACCES;
                return -1;
            }
        } else if (log_fd >= 0 && branch[0]) {
            dprintf(log_fd, "%ld save %s (first from this call path)\n", (long)time(NULL), branch);
        }
        branch[0] = 0;
    }
    return open(path, flags, mode);
}

static int my_socket(int domain, int type, int protocol) {
    int fd = socket(domain, type, protocol);
    if (fd >= 0 && udp_service && type == SOCK_DGRAM && (domain == AF_INET || domain == AF_INET6))
        setsockopt(fd, SOL_SOCKET, SO_NET_SERVICE_TYPE, &udp_service, sizeof udp_service);
    return fd;
}

#define INTERPOSE(fn)                                                         \
    __attribute__((used, section("__DATA,__interpose"))) static const struct { \
        const void *replacement, *original;                                   \
    } interpose_##fn = {my_##fn, fn}
INTERPOSE(open);
INTERPOSE(socket);
