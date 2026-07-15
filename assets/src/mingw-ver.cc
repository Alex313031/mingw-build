// mingw-ver -- one self-contained binary that tells you everything about the
// MinGW-w64 toolchain it ships in, at a glance. Run it (double-click or from a
// terminal) and it reports: the MinGW-w64 version, whether this is a GCC or an
// LLVM/Clang build and that compiler's version, the C/C++ stdlib, the linked
// CRT, the target Windows floor + SIMD baseline + thread model + exception
// model, the build date and the exact source commits it was built from, and the
// host OS it is currently running on (the real NT version via RtlGetVersion, or
// the Linux kernel).
//
// Copyright (c) 2026 Alex313031.
//
// "Multiple sources": compile-time macros from the compiler and the mingw-w64
// headers, a handful of -D defines the build injects for things the headers
// don't expose (git refs, versions, config), and a runtime OS query.

#include <cstdio>
#include <cstring>
#include <cstdlib>

#ifdef _WIN32
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  include <windows.h>
#else
#  include <sys/utsname.h>
#endif

// mingw-w64 headers expose __MINGW64_VERSION_*; only present on mingw targets.
#if defined(__MINGW32__) || defined(__MINGW64__)
#  include <_mingw.h>
#endif

// ---------------------------------------------------------------------------
// Build-injected facts. Each has an #ifndef fallback so the file still compiles
// and runs standalone (for testing) without the toolchain's -D flags.
// ---------------------------------------------------------------------------
#ifndef MV_KIND
#  if defined(__clang__)
#    define MV_KIND "LLVM/Clang"
#  else
#    define MV_KIND "GCC"
#  endif
#endif
#ifndef MV_TOOLCHAIN_VER
#  define MV_TOOLCHAIN_VER "Unknown"   // build script version (SCRIPTVER)
#endif
#ifndef MV_MINGW_REF
#  define MV_MINGW_REF "Unknown"       // mingw-w64 branch + commit
#endif
#ifndef MV_COMPILER_REF
#  define MV_COMPILER_REF "Unknown"    // llvm-project / gcc branch + commit
#endif
#ifndef MV_CONFIG_GUESS
#  define MV_CONFIG_GUESS "Unknown"
#endif
#ifndef MV_ARCH
#  define MV_ARCH "Unknown"            // e.g. i686
#endif
#ifndef MV_TRIPLE
#  define MV_TRIPLE "Unknown"          // e.g. i686-w64-mingw32
#endif
#ifndef MV_THREADS
#  define MV_THREADS "winpthreads"     // thread model shipped
#endif
#ifndef MV_RUNTIME
#  define MV_RUNTIME "msvcrt"          // crtdll / msvcrt / ucrt
#endif

#define MV_VERSION "1.0.1"             // mingw-ver's own version

// ---------------------------------------------------------------------------
// Compile-time deductions
// ---------------------------------------------------------------------------
// Each of these prefers the value the build injected (authoritative -- it is the
// toolchain talking about itself), and only falls back to the macros of whatever
// compiled this file when a -D was not supplied (i.e. standalone test builds).
// This matters because on the Linux-hosted toolchains mingw-ver is compiled by
// the *build host's* cc, whose macros describe that compiler, not the toolchain.
static const char *compiler_version() {
#if defined(MV_COMPILER)
  return MV_COMPILER;
#elif defined(__clang__)
  return "Clang " __clang_version__;
#elif defined(__GNUC__)
  return "GCC " __VERSION__;
#else
  return "Unknown";
#endif
}

static const char *cxx_stdlib() {
#if defined(MV_STDLIB)
  return MV_STDLIB;
#elif defined(_LIBCPP_VERSION)
  return "libc++";
#elif defined(__GLIBCXX__)
  return "libstdc++";
#else
  return "Unknown";
#endif
}

static const char *exception_model() {
#if defined(MV_EXCEPTIONS)
  return MV_EXCEPTIONS;
#elif defined(__SEH__)
  return "SEH";
#elif defined(__USING_SJLJ_EXCEPTIONS__)
  return "SJLJ";
#elif defined(__GNUC__)
  return "DWARF (DW2)";
#else
  return "Unknown";
#endif
}

static const char *unwind_rtlib() {
#if defined(MV_RTLIB)
  return MV_RTLIB;
#elif defined(__clang__)
  return "compiler-rt + libunwind";
#else
  return "libgcc";
#endif
}

static const char *bitness() {
#if defined(MV_BITS)
  return MV_BITS;
#elif defined(_WIN64) || defined(__x86_64__) || defined(__aarch64__)
  return "64-bit";
#else
  return "32-bit";
#endif
}

// Highest SIMD level of the toolchain's baseline for this arch.
static const char *simd_baseline() {
#if defined(MV_SIMD)
  return MV_SIMD;
#elif defined(__AVX512F__)
  return "AVX-512";
#elif defined(__AVX2__)
  return "AVX2";
#elif defined(__AVX__)
  return "AVX";
#elif defined(__SSE4_2__)
  return "SSE4.2";
#elif defined(__SSE4_1__)
  return "SSE4.1";
#elif defined(__SSSE3__)
  return "SSSE3";
#elif defined(__SSE3__)
  return "SSE3";
#elif defined(__SSE2__)
  return "SSE2";
#elif defined(__SSE__)
  return "SSE";
#elif defined(__MMX__)
  return "MMX";
#else
  return "x87 (no SIMD)";
#endif
}

// The toolchain's default _WIN32_WINNT floor, as a friendly name. Prefer the
// injected value (MV_WIN32_WINNT); fall back to this binary's own _WIN32_WINNT.
static void win32_winnt(char *out, size_t n) {
  unsigned v = 0;
#if defined(MV_WIN32_WINNT)
  v = (unsigned)(MV_WIN32_WINNT);
#elif defined(_WIN32_WINNT)
  v = (unsigned)_WIN32_WINNT;
#endif
  if (!v) { snprintf(out, n, "not set"); return; }
  const char *name;
  switch (v) {
    case 0x0400: name = "Windows NT 4.0"; break;
    case 0x0500: name = "Windows 2000"; break;
    case 0x0501: name = "Windows XP"; break;
    case 0x0502: name = "Windows XP x64 / Server 2003"; break;
    case 0x0600: name = "Windows Vista"; break;
    case 0x0601: name = "Windows 7"; break;
    case 0x0602: name = "Windows 8"; break;
    case 0x0603: name = "Windows 8.1"; break;
    case 0x0A00: name = "Windows 10/11"; break;
    default: name = "Custom"; break;
  }
  snprintf(out, n, "0x%04X (%s)", v, name);
}

static const char *mingw_header_version() {
#if defined(__MINGW64_VERSION_STR)
  return __MINGW64_VERSION_STR;
#else
  return "n/a";
#endif
}

// ---------------------------------------------------------------------------
// Runtime host OS
// ---------------------------------------------------------------------------
#ifdef _WIN32
static const char *nt_friendly(unsigned major, unsigned minor, unsigned build) {
  if (major == 4) return "Windows NT 4.0";
  if (major == 5 && minor == 0) return "Windows 2000";
  if (major == 5 && minor == 1) return "Windows XP";
  if (major == 5 && minor == 2) return "Windows XP x64 / Server 2003";
  if (major == 6 && minor == 0) return "Windows Vista / Server 2008";
  if (major == 6 && minor == 1) return "Windows 7 / Server 2008 R2";
  if (major == 6 && minor == 2) return "Windows 8 / Server 2012";
  if (major == 6 && minor == 3) return "Windows 8.1 / Server 2012 R2";
  if (major == 10) return build >= 22000 ? "Windows 11" : "Windows 10";
  return "Windows (Unknown)";
}

static void host_os(char *out, size_t n) {
  // RtlGetVersion is accurate (GetVersionEx lies on 8.1+) and present since
  // Windows 2000, but NOT on NT 4.0 -- so resolve it dynamically and fall back
  // to GetVersionExW (which every NT ships and is accurate pre-8.1).
  typedef LONG(WINAPI * RtlGetVersion_t)(PRTL_OSVERSIONINFOW);
  unsigned major = 0, minor = 0, build = 0;
  bool ok = false;
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  if (ntdll) {
    RtlGetVersion_t p = (RtlGetVersion_t)(void *)GetProcAddress(ntdll, "RtlGetVersion");
    if (p) {
      RTL_OSVERSIONINFOW vi;
      memset(&vi, 0, sizeof(vi));
      vi.dwOSVersionInfoSize = sizeof(vi);
      if (p(&vi) == 0) {
        major = vi.dwMajorVersion; minor = vi.dwMinorVersion; build = vi.dwBuildNumber;
        ok = true;
      }
    }
  }
  if (!ok) {
    OSVERSIONINFOW vi;
    memset(&vi, 0, sizeof(vi));
    vi.dwOSVersionInfoSize = sizeof(vi);
#if defined(__GNUC__)
#  pragma GCC diagnostic push
#  pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif
    if (GetVersionExW(&vi)) {
      major = vi.dwMajorVersion; minor = vi.dwMinorVersion; build = vi.dwBuildNumber;
      ok = true;
    }
#if defined(__GNUC__)
#  pragma GCC diagnostic pop
#endif
  }
  if (ok)
    snprintf(out, n, "%s (NT %u.%u build %u)", nt_friendly(major, minor, build),
             major, minor, build);
  else
    snprintf(out, n, "Windows (version query failed)");
}

// Pause only when launched standalone (e.g. from Explorer), so the window does
// not vanish before it can be read. GetConsoleProcessList is XP+, so resolve it
// dynamically; if absent (NT4/2000) assume a real console and don't pause.
static bool launched_from_gui() {
  typedef DWORD(WINAPI * GCPL_t)(LPDWORD, DWORD);
  HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
  if (!k32) return false;
  GCPL_t p = (GCPL_t)(void *)GetProcAddress(k32, "GetConsoleProcessList");
  if (!p) return false;
  DWORD ids[2];
  return p(ids, 2) <= 1;
}
#else
static void host_os(char *out, size_t n) {
  struct utsname u;
  if (uname(&u) == 0)
    snprintf(out, n, "%s %s (%s)", u.sysname, u.release, u.machine);
  else
    snprintf(out, n, "Unknown");
}
#endif

// ---------------------------------------------------------------------------
static void print_banner(bool json) {
  char winnt[64], os[256];
  win32_winnt(winnt, sizeof winnt);
  host_os(os, sizeof os);

  if (json) {
    printf("{\n");
    printf("  \"toolchain\": \"MinGW-w64 %s build %s\",\n", MV_KIND, MV_TOOLCHAIN_VER);
    printf("  \"arch\": \"%s\",\n", MV_ARCH);
    printf("  \"triple\": \"%s\",\n", MV_TRIPLE);
    printf("  \"bitness\": \"%s\",\n", bitness());
    printf("  \"mingw_w64\": \"%s\",\n", MV_MINGW_REF);
    printf("  \"mingw_headers\": \"%s\",\n", mingw_header_version());
    printf("  \"compiler\": \"%s\",\n", compiler_version());
    printf("  \"compiler_source\": \"%s\",\n", MV_COMPILER_REF);
    printf("  \"cxx_stdlib\": \"%s\",\n", cxx_stdlib());
    printf("  \"rtlib\": \"%s\",\n", unwind_rtlib());
    printf("  \"crt\": \"%s\",\n", MV_RUNTIME);
    printf("  \"threads\": \"%s\",\n", MV_THREADS);
    printf("  \"exceptions\": \"%s\",\n", exception_model());
    printf("  \"target_floor\": \"%s\",\n", winnt);
    printf("  \"simd_baseline\": \"%s\",\n", simd_baseline());
    printf("  \"config_guess\": \"%s\",\n", MV_CONFIG_GUESS);
    printf("  \"built\": \"%s\",\n", __DATE__);
    printf("  \"host_os\": \"%s\"\n", os);
    printf("}\n");
    return;
  }

  printf("\n");
  printf("  MinGW toolchain  --  %s build, version %s\n", MV_KIND, MV_TOOLCHAIN_VER);
  printf("  ------------------------------------------------------------\n");
  printf("  Arch Triple      : %s  (%s, %s)\n", MV_ARCH, MV_TRIPLE, bitness());
  printf("  MinGW-w64        : %s\n", MV_MINGW_REF);
  printf("  MinGW headers    : %s\n", mingw_header_version());
  printf("  Compiler         : %s\n", compiler_version());
  printf("  Compiler source  : %s\n", MV_COMPILER_REF);
  printf("  C++ stdlib       : %s\n", cxx_stdlib());
  printf("  Runtime lib      : %s\n", unwind_rtlib());
  printf("  C runtime (CRT)  : %s\n", MV_RUNTIME);
  printf("  Thread model     : %s\n", MV_THREADS);
  printf("  Exception model  : %s\n", exception_model());
  printf("  Target floor     : %s\n", winnt);
  printf("  SIMD baseline    : %s\n", simd_baseline());
  printf("  config.guess     : %s\n", MV_CONFIG_GUESS);
  printf("  Built            : %s\n", __DATE__);
  printf("  ------------------------------------------------------------\n");
  printf("  Running on       : %s\n", os);
  printf("\n");
}

static void print_help(const char *argv0) {
  printf("mingw-ver %s -- report this MinGW-w64 toolchain's versions.\n", MV_VERSION);
  printf("Usage: %s [--json | --version | --help]\n", argv0);
  printf("  (no args)   print the toolchain banner\n");
  printf("  --json      machine-readable output\n");
  printf("  --version   print mingw-ver's own version\n");
  printf("  --help      this help\n");
}

int main(int argc, char **argv) {
  bool json = false;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--json")) json = true;
    else if (!strcmp(argv[i], "--version")) { printf("mingw-ver %s\n", MV_VERSION); return 0; }
    else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) { print_help(argv[0]); return 0; }
    else { fprintf(stderr, "mingw-ver: Unknown option '%s' (try --help)\n", argv[i]); return 2; }
  }

  print_banner(json);

#ifdef _WIN32
  if (!json && launched_from_gui()) {
    printf("Press Enter to exit...");
    fflush(stdout);
    getchar();
  }
#endif
  return 0;
}
