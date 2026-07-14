/*
 * Toolchain entry-point wrapper for the legacy MinGW-w64 + LLVM toolchain.
 * Unicode on Windows: wmain + wide Win32/CRT calls throughout.
 *
 * Modelled on mstorsjo/llvm-mingw's clang-target-wrapper.c, extended for this
 * fork to also dispatch the binutils-style llvm-* tools and to inject the
 * legacy PE subsystem/OS-version link defaults into the clang drivers.
 *
 * One tiny executable is compiled per arch prefix and copied to every
 * <triple>-<tool>[.exe] entry point, so the prefix ships a single clang / lld /
 * llvm-* set instead of N copies of a ~100 MB binary. At runtime it inspects
 * its own filename (the real module path on Windows) and either:
 *   - clang drivers (clang/clang++/gcc/g++/cc/c++): exec clang with
 *       -target TARGET  --driver-mode={gcc,g++}  EXTRA  <args>
 *   - binutils tools (ar/ranlib/nm/strip/objcopy/objdump/dlltool/windres/
 *     strings/addr2line/size/ld): exec the matching llvm-<tool> (ld -> ld.lld,
 *     readelf -> llvm-readobj in readelf mode) with <args> unchanged.
 *   - as: drive clang's integrated assembler (-x assembler -c).
 * The real binary is located next to the wrapper; clang finds its sysroot from
 * the target triple's sibling dir (../TARGET), same as upstream.
 *
 * A narrow (char/main) build path is kept for non-Windows host testing; the
 * shared logic goes through the X* macro layer below.
 *
 * Compile-time defines:
 *   TARGET - the clang target triple, e.g. "i586-w64-mingw32"
 *   EXTRA  - space-separated default flags for the clang drivers (the PE
 *            subsystem/OS-version link flags); may be empty.
 */

#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <tchar.h>
#include <windows.h>
#include <process.h>
#include <wchar.h>
#include <wctype.h>
typedef wchar_t xchar;
#define XMAIN wmain
#define XL_(s) L##s
#define XL(s) XL_(s)
#define XSTRRCHR wcsrchr
#define XSTRCMP wcscmp
#define XSTRLEN wcslen
#define XSTRDUP _wcsdup
#define XSTRCPY wcscpy
#define XSTRCAT wcscat
#define XSTRNCPY wcsncpy
#define XTOLOWER towlower
#define XPERROR _wperror
#define SELF_MAX MAX_PATH
#else
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <limits.h>
typedef char xchar;
#define XMAIN main
#define XL_(s) s
#define XL(s) XL_(s)
#define XSTRRCHR strrchr
#define XSTRCMP strcmp
#define XSTRLEN strlen
#define XSTRDUP strdup
#define XSTRCPY strcpy
#define XSTRCAT strcat
#define XSTRNCPY strncpy
#define XTOLOWER tolower
#define XPERROR perror
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
#define SELF_MAX PATH_MAX
#endif

#ifndef TARGET
#define TARGET ""
#endif
#ifndef EXTRA
#define EXTRA ""
#endif
/* Widen the baked narrow string literals on the Unicode build. */
#define WTARGET XL(TARGET)
#define WEXTRA XL(EXTRA)

static void *xmalloc(size_t n) {
  void *p = malloc(n);
  if (!p) {
    fputs("wrapper: out of memory\n", stderr);
    exit(1);
  }
  return p;
}

static xchar *xxstrdup(const xchar *s) {
  xchar *r = XSTRDUP(s);
  if (!r) {
    fputs("wrapper: out of memory\n", stderr);
    exit(1);
  }
  return r;
}

/* Full path of THIS executable. On Windows this is the real module path
 * (GetModuleFileNameW), so dispatch keys on the actual stub filename rather
 * than on whatever argv[0] the caller happened to set. Elsewhere (host build /
 * testing) fall back to argv[0]. */
static xchar *self_path(const xchar *argv0) {
  static xchar buf[SELF_MAX];
#ifdef _WIN32
  DWORD n = GetModuleFileNameW(NULL, buf, SELF_MAX);
  if (n == 0 || n >= SELF_MAX) {
    XSTRNCPY(buf, argv0, SELF_MAX - 1);
    buf[SELF_MAX - 1] = 0;
  }
#else
  XSTRNCPY(buf, argv0, SELF_MAX - 1);
  buf[SELF_MAX - 1] = 0;
#endif
  return buf;
}

/* Directory of PATH, including the trailing separator (heap-allocated). */
static xchar *dir_of(const xchar *path) {
  xchar *buf = xxstrdup(path);
  xchar *p = XSTRRCHR(buf, XL('/'));
  xchar *q = XSTRRCHR(buf, XL('\\'));
  if (q > p)
    p = q;
  if (p) {
    p[1] = 0;
  } else {
    buf[0] = XL('.');
#ifdef _WIN32
    buf[1] = XL('\\');
#else
    buf[1] = XL('/');
#endif
    buf[2] = 0;
  }
  return buf;
}

/* basename(PATH) with a trailing ".exe" removed (heap-allocated). */
static xchar *tool_basename(const xchar *path) {
  const xchar *b = path;
  const xchar *s1 = XSTRRCHR(path, XL('/'));
  const xchar *s2 = XSTRRCHR(path, XL('\\'));
  const xchar *s = s1 > s2 ? s1 : s2;
  if (s)
    b = s + 1;
  xchar *name = xxstrdup(b);
  size_t len = XSTRLEN(name);
  if (len > 4) {
    xchar *e = name + len - 4;
    if (e[0] == XL('.') && XTOLOWER(e[1]) == XL('e') &&
        XTOLOWER(e[2]) == XL('x') && XTOLOWER(e[3]) == XL('e'))
      e[0] = 0;
  }
  return name;
}

/* Split a mutable string on spaces into argv-style tokens, in place. */
static int split_ws(xchar *s, xchar **out, int max) {
  int n = 0;
  while (*s) {
    while (*s == XL(' '))
      s++;
    if (!*s)
      break;
    if (n < max)
      out[n] = s;
    n++;
    while (*s && *s != XL(' '))
      s++;
    if (*s)
      *s++ = 0;
  }
  return n;
}

int XMAIN(int argc, xchar **argv) {
  xchar *self = self_path(argv[0]);
  xchar *dir = dir_of(self);
  xchar *base = tool_basename(self);

  /* tool = segment after the last '-' (e.g. "...-mingw32-clang++" -> "clang++") */
  xchar *dash = XSTRRCHR(base, XL('-'));
  const xchar *tool = dash ? dash + 1 : base;

  const xchar *real = NULL; /* binary file name (in our dir) */
  const xchar *mode = NULL; /* clang --driver-mode value, or NULL for binutils */
  int assemble = 0;         /* 1 => drive clang's integrated assembler (as) */

  if (!XSTRCMP(tool, XL("clang")) || !XSTRCMP(tool, XL("gcc")) ||
      !XSTRCMP(tool, XL("cc"))) {
    real = XL("clang");
    mode = XL("gcc");
  } else if (!XSTRCMP(tool, XL("clang++")) || !XSTRCMP(tool, XL("g++")) ||
             !XSTRCMP(tool, XL("c++"))) {
    real = XL("clang");
    mode = XL("g++");
  } else if (!XSTRCMP(tool, XL("ld"))) {
    real = XL("ld.lld");
  } else if (!XSTRCMP(tool, XL("windres"))) {
    real = XL("llvm-windres");
  } else if (!XSTRCMP(tool, XL("readelf"))) {
    /* No llvm-readelf is shipped; llvm-readobj emits readelf-style (GNU) output
     * when argv[0] contains "readelf" (it does here), so route readelf there. */
    real = XL("llvm-readobj");
  } else if (!XSTRCMP(tool, XL("as"))) {
    /* LLVM ships no standalone GNU as; drive clang's integrated assembler.
     * assemble=1 injects "-target T -x assembler -c" below, so
     * `as in.s -o out.o` produces an object. Best-effort: covers file-in/-o-out
     * assembly, not the full GNU as CLI (e.g. --32). */
    real = XL("clang");
    assemble = 1;
  } else {
    /* ar, ranlib, nm, strip, objcopy, objdump, dlltool, strings, addr2line, size */
    xchar *n = xmalloc((XSTRLEN(tool) + 6) * sizeof(xchar));
    XSTRCPY(n, XL("llvm-"));
    XSTRCAT(n, tool);
    real = n;
  }

  /* Full path of the real binary: <dir><real>[.exe] */
  xchar *exe = xmalloc((XSTRLEN(dir) + XSTRLEN(real) + 6) * sizeof(xchar));
  XSTRCPY(exe, dir);
  XSTRCAT(exe, real);
#ifdef _WIN32
  XSTRCAT(exe, XL(".exe"));
#endif

  /* Split EXTRA (clang drivers only) into argv tokens. */
  int extra_count = 0;
  xchar **extra_argv = NULL;
  if (mode && WEXTRA[0]) {
    xchar *extra = xxstrdup(WEXTRA);
    int cap = (int)(XSTRLEN(extra) / 2 + 2);
    extra_argv = xmalloc(sizeof(xchar *) * cap);
    extra_count = split_ws(extra, extra_argv, cap);
  }

  /* Assemble the new argv. Keep argv[0] for nicer diagnostics. */
  xchar drivermode[40];
  xchar **newargv = xmalloc(sizeof(xchar *) * (argc + extra_count + 8));
  int n = 0;
  newargv[n++] = argv[0];
  if (mode) {
    newargv[n++] = (xchar *)XL("-target");
    newargv[n++] = (xchar *)WTARGET;
    XSTRCPY(drivermode, XL("--driver-mode="));
    XSTRCAT(drivermode, mode);
    newargv[n++] = drivermode;
    for (int i = 0; i < extra_count; i++)
      newargv[n++] = extra_argv[i];
  }
  if (assemble) {
    newargv[n++] = (xchar *)XL("-target");
    newargv[n++] = (xchar *)WTARGET;
    newargv[n++] = (xchar *)XL("-x");
    newargv[n++] = (xchar *)XL("assembler");
    newargv[n++] = (xchar *)XL("-c");
  }
  for (int i = 1; i < argc; i++)
    newargv[n++] = argv[i];
  newargv[n] = NULL;

#ifdef _WIN32
  /* _wspawnv with _P_WAIT so the wrapper's exit code mirrors the real tool's
   * (true exec semantics are unreliable on Windows). The CRT quotes argv
   * elements containing spaces; embedded quotes/trailing backslashes are not
   * handled - switch to manual quoting + CreateProcessW if that ever bites. */
  intptr_t rc = _wspawnv(_P_WAIT, exe, (const wchar_t *const *)newargv);
  if (rc == -1) {
    XPERROR(exe);
    return 1;
  }
  return (int)rc;
#else
  execv(exe, newargv);
  XPERROR(exe);
  return 1;
#endif
}
