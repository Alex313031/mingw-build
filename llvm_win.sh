#!/bin/bash

# Copyright (C) 2025 Kyle Schwarz <zeranoe@gmail.com>
# Copyright (C) 2026 Alex Frick <alex313031@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Windows-HOSTED LLVM/Clang variant. This is the Canadian-cross counterpart of
# llvm_linux.sh: it runs on Linux but produces a MinGW-w64 + LLVM
# toolchain whose driver binaries (clang.exe, lld, the llvm-* tools, gendef.exe)
# RUN ON WINDOWS, exactly as gcc_win.sh is the Windows-hosted counterpart
# of gcc_linux.sh for the GCC flavor.
#
# Two phases per arch:
#   Phase 1 - build a normal Linux-hosted llvm-mingw toolchain (clang/lld + all
#             target runtimes) into an intermediate prefix. This provides (a) the
#             cross clang that compiles Phase 2, (b) the native llvm-tblgen /
#             clang-tblgen the LLVM cross-build needs, and (c) the target runtime
#             libraries (compiler-rt/libunwind/libc++/CRT/winpthreads), which are
#             identical PE bits regardless of where the compiler runs.
#   Phase 2 - cross-compile LLVM itself (clang/lld/llvm-* as Windows .exe, static
#             so they carry no DLL deps) with the Phase 1 clang, reuse Phase 1's
#             target sysroot + compiler-rt, build gendef.exe, and lay down the
#             Windows toolchain wrappers/clang config.
#
# EXPERIMENTAL / UNTESTED: cross-hosting LLVM is finicky. The most likely places
# to need tuning are the Phase 2 LLVM cross CMake (native tblgen wiring, static
# libc++ into clang.exe) and the Windows wrapper/clang-config mechanism. The
# legacy floor (no-SSE i586, NT 4.0/2000) is shared with the Linux-hosted script.

SCRIPTNAME=$(basename "$0")
SCRIPTVER="2.3.3"

export HERE=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ROOT_PATH="$HERE/build/win_llvm"
SRC_PATH="$ROOT_PATH/src"
BLD_PATH="$ROOT_PATH/bld"
LOG_FILE="$ROOT_PATH/build.log"

# Source URLs, using GitHub instead of originals for cloning speed
MINGW_W64_URL="https://github.com/mingw-w64/mingw-w64" # https://git.code.sf.net/p/mingw-w64/mingw-w64
LLVM_URL="https://github.com/llvm/llvm-project"
MAKE_URL="https://ftpmirror.gnu.org/make" # GNU make tarballs (ftpmirror redirects to a nearby GNU mirror)
# What branches to checkout
MINGW_W64_BRANCH="v14.x"
LLVM_BRANCH="release/22.x"
MAKE_VERSION="4.4.1"

# Controls minimum Windows target, should always be set non-zero later.
WIN32_WINNT="0"

# Thread model
ENABLE_THREADS="--enable-threads=posix"

# CRT compatibility. crtdll (win 95), or msvcrt (Win 98/NT 4.0 with update, 2000+)
LINKED_RUNTIME="msvcrt"

JOB_COUNT=$(getconf _NPROCESSORS_ONLN)

IS_DEBUG=false
USE_MMX=false
USE_SSE2=false
USE_SSE3=false
USE_SSE41=false
USE_SSE42=false
USE_AVX=false
USE_AVX2=false
USE_AVX512=false

# Colors
YEL='\033[1;33m' # Yellow
CYA='\033[1;96m' # Cyan
RED='\033[1;31m' # Red
GRE='\033[1;32m' # Green
c0='\033[0;00m'  # Reset Text
bold='\033[1;37m' # Bold Text
underline='\033[4m' # Underline Text

show_help() {
  cat <<EOF
Runs on Linux; produces a Windows-HOSTED MinGW-w64 + LLVM toolchain (clang.exe,
lld, llvm-* and gendef.exe run on Windows) via a two-phase Canadian cross.

Usage:
  $SCRIPTNAME <arch> [options]

Archs:
  i586         - Windows 32-bit for old CPUs without SSE (Intel Pentium (MMX), Pentium II, AMD K5, K6, K7)
  i686 | x32   - Windows 32-bit for CPUs with SSE (Intel Pentium III and newer, Athlon XP and newer)
  x86_64 | x64 - Windows 64-bit for CPUs with SSE2 (Intel Prescott, AMD K8 and newer)

Options:
  -h, --help                  Show this help.
  -v, --verbose               Log build output to the console as well as the build.log file.
  -a, --all                   Build all three archs: i586, i686 and x86_64.
  --version                   Show script version.
  --deps                      Install prerequisites for using this script (Ubuntu/Debian only).
  -j <count>, --jobs <count>  Override make/ninja job count. (default: $JOB_COUNT)
  --package                   After a successful build, zip each built arch into <root>/<arch>.zip (x86_64 becomes x64.zip).
  --prefix <path>             Change install location. (default: $ROOT_PATH/<arch>)
  --root <path>               Location for sources, build artifacts and the resulting compiler. (default: $ROOT_PATH)
  --keep-artifacts            Don't remove source and build files (incl. the Phase 1 Linux-hosted intermediate) after a successful build.
  --disable-threads           Disable pthreads and STL <thread>.
  -c, --cached-sources        Use existing sources instead of downloading new ones and patching them.
  --incremental               Fast iteration: reuse existing sources, build trees and install prefix, re-apply patches, and let Ninja rebuild only what changed. Implies -c and --keep-artifacts; needs a prior --keep-artifacts/--incremental build. (rsync needed for the sysroot sync)
  -d, --download-sources      Only download sources, then exit; for making local modifications.
  -p, --patch                 Only apply patches to already-downloaded sources, then exit; needs no arch.
  --clang-format              Build only clang-format.exe (no full toolchain) and copy it into <prefix>/bin; reuses Phase 1 if present.
  --clean                     Removes all sources and build artifacts, and output (keeps the previous build.log as build.log.old).
  --dist-clean                Like --clean but keeps the src/ tree (downloaded + patched sources), so a later build with -c skips re-downloading and re-patching.
  --llvm-url <url>            Set LLVM source URL, (default: $LLVM_URL)
  --llvm-branch <branch>      Set LLVM branch, (default: $LLVM_BRANCH)
  --mingw-url <url>           Set MinGW-w64 source url, (default: $MINGW_W64_URL)
  --mingw-branch <branch>     Set MinGW-w64 branch, (default: $MINGW_W64_BRANCH)
  --crtlib <runtime>          Set MinGW Linked CRT (crtdll, msvcrt, ucrt); should usually be left alone. (default: $LINKED_RUNTIME)
  --win32-winnt <version>     Set default _WIN32_WINNT value for minimum Windows version target. (default: $WIN32_WINNT)

Compilation Flags:
  --debug                     Create a debug build (default is release mode).
  --mmx                       Compile with MMX, only has an effect on i586 builds. (default: $USE_MMX)
  --sse2                      Compile with SSE2, only has an effect on i686 builds. (default: $USE_SSE2)
  --sse3                      Compile with SSE3, i686 & x86_64 (default: $USE_SSE3)
  --sse41                     Compile with SSE4.1, i686 & x86_64 (default: $USE_SSE41)
  --sse42                     Compile with SSE4.2, i686 & x86_64 (default: $USE_SSE42)
  --avx                       Compile with AVX, x86_64 only. (default: $USE_AVX)
  --avx2                      Compile with AVX2, x86_64 only. (default: $USE_AVX2)
  --avx512                    Compile with AVX-512, x86_64 only, experimental. (default: $USE_AVX512)

For possible _WIN32_WINNT values, see:
https://learn.microsoft.com/en-us/cpp/porting/modifying-winver-and-win32-winnt

EOF
}

show_version() {
  printf "\n ${bold} %s Version %s \n\n" "$SCRIPTNAME" "$SCRIPTVER"
  exit 0
}

error_exit() {
  local error_msg="$1"
  shift 1

  if [ "$error_msg" ]; then
    log "${RED}%s${c0}\n" "$error_msg" >&2
  else
    log "${RED}An error occured.${c0}\n" >&2
  fi
  exit 1
}

arg_error() {
  local error_msg="$1"
  shift 1

  error_exit "$error_msg, see --help for options" "$error_msg"
}

execute() {
  local info_msg="$1"
  local error_msg="$2"
  shift 2

  if [ ! "$error_msg" ]; then
    error_msg="error"
  fi

  if [ "$info_msg" ]; then
    printf "${CYA}(%d/%d): %s${c0}\n" "$CURRENT_STEP" "$TOTAL_STEPS" "$info_msg"
    CURRENT_STEP=$((CURRENT_STEP + 1))
  fi
  if [ "$VERBOSE" == "1" ]; then
    # mirror output to the console as well as the log file
    # (process substitution keeps "$@"'s exit status, unlike a pipe to tee)
    "$@" > >(tee -a "$LOG_FILE") 2>&1 || error_exit "$error_msg, check $LOG_FILE for details."
  else
    "$@" >>"$LOG_FILE" 2>&1 || error_exit "$error_msg, check $LOG_FILE for details."
  fi
}

log() {
  # Print a message (printf-style: format then args) to the console with color,
  # and append a color-stripped copy to the log file so build.log stays clean.
  # Unlike execute(), it runs no command and does no error handling. The log
  # write is skipped until the log directory exists (e.g. early arg errors).
  printf "$@"
  if [ -d "$(dirname "$LOG_FILE")" ]; then
    printf "$@" | sed -E 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
  fi
}

create_dir() {
  local path="$1"
  shift 1

  local MKDIRFLAGS="-p"
  if [ "$VERBOSE" == "1" ]; then
    MKDIRFLAGS+=" -v"
  fi
  execute "" "Unable to create directory '$path'" \
      mkdir $MKDIRFLAGS "$path"
}

remove_path() {
  local path="$1"
  shift 1

  local RMDIRFLAGS="-f -r"
  if [ "$VERBOSE" == "1" ]; then
    RMDIRFLAGS+=" -v"
  fi
  execute "" "Unable to remove path '$path'" \
      rm $RMDIRFLAGS "$path"
}

clean_build() {
  local keep_src="$1"
  if [ ! -d "$ROOT_PATH" ]; then
    printf "${YEL}Nothing to clean: '%s' does not exist.${c0}\n" "$ROOT_PATH"
    return
  fi

  local MVFLAGS="-f"
  local RMFLAGS="-rf"
  if [ "$VERBOSE" == "1" ]; then
    MVFLAGS+=" -v"
    RMFLAGS+=" -v"
  fi

  # keep the previous build log around as build.log.old
  if [ -f "$LOG_FILE" ]; then
    mv $MVFLAGS "$LOG_FILE" "$LOG_FILE.old"
  fi

  # nuke everything else under the build directory, preserving build.log.old.
  # With --dist-clean also preserve the downloaded+patched src tree so a later
  # build can reuse it via -c instead of re-cloning and re-patching.
  local keep_args=( ! -name "$(basename "$LOG_FILE").old" )
  if [ "$keep_src" ]; then
    keep_args+=( ! -name "$(basename "$SRC_PATH")" )
  fi
  find "$ROOT_PATH" -mindepth 1 -maxdepth 1 \
      "${keep_args[@]}" -exec rm $RMFLAGS {} +

  if [ "$keep_src" ]; then
    printf "${YEL}Cleaned '%s' (kept %s/).${c0}\n" "$ROOT_PATH" "$(basename "$SRC_PATH")"
  else
    printf "${YEL}Cleaned '%s'.${c0}\n" "$ROOT_PATH"
  fi
}

change_dir() {
  local path="$1"
  shift 1

  execute "" "Unable to cd to directory '$path'" \
      cd "$path"
}

download_sources() {
  remove_path "$SRC_PATH"
  create_dir "$SRC_PATH"
  change_dir "$SRC_PATH"
  # --progress forces git's progress meter even when writing to the log; only
  # want it in verbose mode (otherwise it spams build.log with \r updates)
  local git_progress=""
  [ "$VERBOSE" == "1" ] && git_progress="--progress"
  printf "${GRE}Downloading sources${c0}\n"
  execute "Cloning MinGW source..." "Unable to clone MinGW-w64, to use the official mirror: --mingw-url 'https://git.code.sf.net/p/mingw-w64/mingw-w64'" \
      git clone $git_progress --depth 1 -b "$MINGW_W64_BRANCH" \
      "$MINGW_W64_URL" mingw-w64

  # The LLVM monorepo is large; --depth 1 keeps the clone manageable. It carries
  # clang, lld, compiler-rt, libunwind, libcxx and libcxxabi - everything that
  # replaces GCC + binutils + libgcc + libstdc++.
  execute "Cloning LLVM source..." "Unable to clone LLVM" \
      git clone $git_progress --depth 1 -b "$LLVM_BRANCH" \
      "$LLVM_URL" llvm-project

  # GNU make ships as a release tarball (its git tree needs a heavy gnulib
  # ./bootstrap; the tarball has a ready ./configure + gnulib baked in).
  execute "Downloading GNU make $MAKE_VERSION source..." "Unable to download GNU make from $MAKE_URL (canonical: https://ftp.gnu.org/gnu/make/)" \
      curl -fsSL "$MAKE_URL/make-$MAKE_VERSION.tar.gz" -o "make-$MAKE_VERSION.tar.gz"
  execute "Extracting GNU make source..." "Unable to extract GNU make" \
      tar -xf "make-$MAKE_VERSION.tar.gz"
  mv "make-$MAKE_VERSION" make

  execute "Copying config.guess..." "" \
      cp -fv ${HERE}/assets/config.guess ./
  printf "${GRE}Done downloading sources!${c0}\n"
}

apply_patches() {
  log "${GRE}Applying patches...${c0}\n"
  create_dir "$SRC_PATH/patches"
  execute "" "Unable to copy patches" \
      cp -fv "$HERE"/patches/*/*.patch "$SRC_PATH/patches/"
  # NOTE: the GCC/binutils patches (gcc-stdcall-align, gcc-trap-terminate,
  # gcc-tzdb-getdynamic, binutils-dlltool-zero-ordinals) do not apply to an
  # LLVM toolchain and are intentionally skipped. Only the MinGW-w64 patches,
  # which patch sources still used here, are applied (plus an LLVM patch below).
  printf "${YEL}  Patching LLVM...${c0}\n"
  change_dir "$SRC_PATH/llvm-project"
  # compiler-rt's emutls.c calls InitOnceExecuteOnce(), a Vista+ API. The patch
  # is self-guarding (#if _WIN32_WINNT >= 0x0600) so it is a no-op on modern
  # targets and provides a pre-Vista fallback for NT 4.0/2000/XP builds.
  execute "" "Failed to apply compiler-rt-emutls-pre-vista.patch" \
      git apply --reject ../patches/compiler-rt-emutls-pre-vista.patch
  # libc++'s Windows locale shim uses the per-locale "_l" ctype helpers that the
  # legacy msvcrt.dll (NT 4.0/2000/XP target) lacks. The patch is self-guarding
  # (only active for non-UCRT msvcrt < 0x0800) so it is a no-op on UCRT builds.
  execute "" "Failed to apply libcxx-legacy-msvcrt-locale.patch" \
      git apply --reject ../patches/libcxx-legacy-msvcrt-locale.patch
  # libc++ calls the bounds-checked wcrtomb_s(), which the legacy msvcrt.dll
  # lacks; the patch supplies a local shim (self-guarding, no-op on UCRT).
  execute "" "Failed to apply libcxx-legacy-msvcrt-wcrtomb_s.patch" \
      git apply --reject ../patches/libcxx-legacy-msvcrt-wcrtomb_s.patch
  # libunwind's Win32 RWMutex uses SRWLOCK (Vista+). The patch adds a pre-Vista
  # CRITICAL_SECTION fallback (self-guarding on _WIN32_WINNT < 0x0600), avoiding
  # a winpthreads dependency in libunwind.
  execute "" "Failed to apply libunwind-rwmutex-pre-vista.patch" \
      git apply --reject ../patches/libunwind-rwmutex-pre-vista.patch
  # libc++'s std::filesystem uses Vista+ APIs (GetFileInformationByHandleEx,
  # CreateSymbolicLinkW, GetFinalPathNameByHandleW, SetFileInformationByHandle).
  # The patch adds NT 4.0/2000/XP fallbacks (self-guarding on _WIN32_WINNT <
  # 0x0600); symlink/realpath/fchmod degrade to "not supported" on those targets.
  execute "" "Failed to apply libcxx-legacy-filesystem.patch" \
      git apply --reject ../patches/libcxx-legacy-filesystem.patch
  # libc++ std::thread::hardware_concurrency() uses GetActiveProcessorCount
  # (Windows 7+); the patch falls back to GetSystemInfo() on older targets
  # (self-guarding on _WIN32_WINNT < 0x0601). Needed on LLVM 22.x (20.x already
  # used GetSystemInfo).
  execute "" "Failed to apply libcxx-thread-getsysteminfo.patch" \
      git apply --reject ../patches/libcxx-thread-getsysteminfo.patch
  # Lets the Windows-hosted clang/lld/llvm-* LOAD on XP/2000. Gated < Win7
  # (0x0601): the patch also defers Win7 processor-group APIs, so a Vista (0x0600)
  # floor still needs it for the binary to load.
  if (( WIN32_WINNT < 0x0601 )); then
    execute "" "Failed to apply llvm-support-pre-vista.patch" \
        git apply --reject ../patches/llvm-support-pre-vista.patch
    # TempFile's atomic temp+rename (FileOutputBuffer -> llvm-rc/windres, lld,
    # llvm-objcopy, ...) renames via the HANDLE-based rename_handle(), which needs
    # SetFileInformationByHandle / GetFinalPathNameByHandleW (Vista+). Pre-Vista,
    # rename by path instead (MoveFileExW fix from llvm-support-pre-vista.patch).
    # No-op above XP (RemoveOnClose is only set when the disposition call fails).
    execute "" "Failed to apply llvm-tempfile-pre-vista.patch" \
        git apply --reject ../patches/llvm-tempfile-pre-vista.patch
  fi
  # clang's DirectoryWatcher (compiled into libclang-cpp.dll) statically imports
  # GetFinalPathNameByHandleW (Vista+), which blocks the DLL from LOADing on
  # XP/2000 -- lib/Support's copy is already handled by the patch above, but this
  # clang call site is separate. Resolve it dynamically. Self-guarding (#if
  # _WIN32_WINNT < 0x0600) so it is a no-op on Vista+ targets; only the Windows
  # host compiles this file (Linux host builds DirectoryWatcher-linux.cpp).
  execute "" "Failed to apply clang-directorywatcher-pre-vista.patch" \
      git apply --reject ../patches/clang-directorywatcher-pre-vista.patch
  # Bake the PE OS/subsystem version into lld's defaults instead of stamping it
  # via the wrappers: lld/COFF picks major/minor from _WIN32_WINNT at COMPILE
  # time (so the Phase 2 LLVM cmake passes -D_WIN32_WINNT=$WIN32_WINNT). Also
  # lets .def version fields be hex. Correct for any target -> applied ungated.
  execute "" "Failed to apply llvm-coff-fixes.patch" \
      git apply --reject ../patches/llvm-coff-fixes.patch
  # Resolve libunwind's EnumProcessModules dynamically so it carries no static
  # psapi import. Lets the build drop the -Wl,--whole-archive -lpsapi hammer (which
  # force-linked ALL of psapi, incl. Vista+ exports XP lacks) for a plain -lpsapi
  # at the end of the link line -- see the psapi comment in build_phase2_windows.
  execute "" "Failed to apply libunwind-psapi-dynamic.patch" \
      git apply --reject ../patches/libunwind-psapi-dynamic.patch
  # push_macro/pop_macro so LLVM Support code sees the caller's legacy _WIN32_WINNT
  # in the code body while the Windows headers stay pinned at 0x0601, plus the
  # re-pins that files pulling in extra Windows headers need (Path.inc shlobj,
  # raw_socket_stream winsock2). Must precede llvm-extra.patch, which rides on the same
  # WindowsSupport.h. NOTE: maintenance-heavy -- new Support files that include
  # extra Windows headers past WindowsSupport.h may need their own re-pin.
  execute "" "Failed to apply llvm-win32-winnt-guard.patch" \
      git apply --reject ../patches/llvm-win32-winnt-guard.patch
  # Runtime Windows host-OS helpers (IsLegacyWindows / GetWindowsOSName / Running*
  # OrGreater) + logging the host OS in clang/lld --version. Windows-host only;
  # behavioral/diagnostic, does NOT fix load-time imports.
  execute "" "Failed to apply llvm-extra.patch" \
      git apply --reject ../patches/llvm-extra.patch
  printf "${YEL}  Patching MinGW...${c0}\n"
  change_dir "$SRC_PATH/mingw-w64"
  execute "" "Failed to apply mingw-gendef-silent.patch" \
      git apply --reject ../patches/mingw-gendef-silent.patch
  if (( WIN32_WINNT < 0x0501 )); then
    execute "" "Failed to apply mingw-rand_s-win2k.patch" \
        git apply --reject ../patches/mingw-rand_s-win2k.patch
  fi
  # GetSystemTimeAsFileTime is Windows 2000+, so the stock gettimeofday.c's
  # static reference to it makes any program using gettimeofday fail to load on
  # NT 4.0. Resolve it dynamically with a GetSystemTime + SystemTimeToFileTime
  # emulation fallback (both present on every NT release). Only NT4 needs it.
  if (( WIN32_WINNT < 0x0500 )); then
    execute "" "Failed to apply mingw-gettimeofday.patch" \
        git apply --reject ../patches/mingw-gettimeofday.patch
  fi
  execute "" "Failed to apply mingw-headers.patch" \
      git apply --reject ../patches/mingw-headers.patch
  execute "" "Unable to mark patches as applied" \
      touch "$SRC_PATH/patches/applied_patches"
  printf "${GRE}Done patching sources!${c0}\n"
  change_dir "$HERE"
}

# Echo "<branch> <commit>" for the git repo at $1, falling back to the
# branch label $2 if HEAD is detached or git can't read the repo.
git_ref() {
  local dir="$1" fallback="$2" branch commit
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    branch="$fallback"
  fi
  commit=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
  printf '%s %s' "$branch" "$commit"
}

# Write a VERSION.txt manifest into an arch's install prefix. All values are
# gathered live: branch/commit from git, config.guess from its timestamp line,
# the script name/version, and the effective build flags for that arch.
# $1 = arch, $2 = install prefix, $3 = host label (e.g. "Windows"),
# $4 = arch-relevant flag lines (KEY=value\n...)
write_version_file() {
  local arch="$1" prefix="$2" host_label="$3" flag_lines="$4"
  local mingw_ref llvm_ref config_guess_ver

  mingw_ref=$(git_ref "$SRC_PATH/mingw-w64" "$MINGW_W64_BRANCH")
  llvm_ref=$(git_ref "$SRC_PATH/llvm-project" "$LLVM_BRANCH")
  config_guess_ver=$(grep -m1 '^timestamp=' "$SRC_PATH/config.guess" | cut -d"'" -f2)

  cat > "$prefix/VERSION.txt" <<EOF
---- Versions ----

MinGW Version: $mingw_ref

LLVM Version: $llvm_ref

config.guess Version: $config_guess_ver

Built using $SCRIPTNAME Version: $SCRIPTVER

---- Build Details ----

Arch: $arch

Host: $host_label

WIN32_WINNT=$WIN32_WINNT
IS_DEBUG=$IS_DEBUG
$flag_lines
EOF
  printf "${GRE}Wrote version file ${bold}${prefix}/VERSION.txt ${c0}\n"
}

copy_extra_files() {
  local triple="$1" prefix="$2"
  local outpath="$prefix/$triple/include"
  log "${GRE}Copying extra headers to $outpath${c0}\n"
  execute "" "Failed to copy sdkddkver.h" cp -fv ${HERE}/patches/mingw/sdkddkver.h $outpath
  execute "" "Failed to copy winsdkver.h" cp -fv ${HERE}/patches/mingw/winsdkver.h $outpath
  # Experimental extras from patches/extra (header-only, unrelated to XP): a
  # universal C/C++ bool fallback and the unsigned-float (ufloat) type. These are
  # language/stdlib headers, so install them next to the compiler's own
  # stdbool.h (its freestanding include dir), NOT in the mingw sysroot beside
  # windows.h.
  local stdinc
  stdinc=$(dirname "$(find "$prefix/lib" -path '*/include/stdbool.h' 2>/dev/null | head -1)")
  [ -d "$stdinc" ] || error_exit "copy_extra_files: no compiler include dir (stdbool.h) under $prefix/lib"
  log "${GRE}Copying stdlib extras to $stdinc${c0}\n"
  execute "" "Failed to copy cstdbool.h" cp -fv ${HERE}/patches/extra/cstdbool.h "$stdinc"
  execute "" "Failed to copy ufloat.h" cp -fv ${HERE}/patches/extra/ufloat.h "$stdinc"
  log "${GRE}Copying logo SVG to $prefix${c0}\n"
  execute "" "Failed to copy mingw.svg" cp -fv ${HERE}/assets/mingw-w64.svg $prefix/mingw.svg
}

# LLVM's install creates the multicall-tool aliases (ld.lld, lld-link, llvm-windres,
# clang++, llvm-dlltool, llvm-ranlib, ...) as symlinks to the base binary. On a
# Linux->Windows cross build those are UNIX symlinks that Windows cannot follow --
# launching one gives "The system cannot execute the specified program" / "The file
# cannot be accessed by the system", and a .zip ships them as dangling 9-byte stubs.
# Replace every symlink under the prefix with a real file. These are multicall
# binaries: they dispatch on argv[0], which is the entry's own filename, so a plain
# duplicate is functionally identical to the symlink. Use a HARDLINK (cp -l) so it
# costs no extra space on the build filesystem -- like upstream llvm-mingw -- falling
# back to a copy across filesystems. NOTE: a .zip/copy to Windows expands hardlinks
# into full copies, so the DISTRIBUTED size still grows (~29 MB, mostly lld.exe's 4
# aliases); Windows has no working symlink for this. Runtime lib symlinks in the
# sysroot get the same treatment (also broken on Windows).
flatten_install_symlinks() {
  local prefix="$1" l tgt n=0
  while IFS= read -r -d '' l; do
    tgt=$(readlink -f "$l" 2>/dev/null) || continue
    [ -f "$tgt" ] || continue   # skip dir symlinks / dangling
    rm -f "$l" && { cp -lf "$tgt" "$l" 2>/dev/null || cp -f "$tgt" "$l"; } && n=$((n + 1))
  done < <(find "$prefix" -type l -print0 2>/dev/null)
  log "${GRE}Flattened $n Unix symlink(s) to real files (Windows can't follow them).${c0}\n"
}

# Generate the familiar <arch>-w64-mingw32-* toolchain entry points in the
# prefix's bin dir. The clang driver infers C vs C++ mode from "++" in argv[0];
# we bake in --target and --sysroot only. Deliberately NO -march/SIMD flags: the
# arch CPU baseline is a build-time property of the runtimes, not something the
# driver should impose on user code (that would override flags a user passes for
# testing). The triple's own default CPU keeps 32-bit conservative (no SSE);
# users opt into SIMD with their own -march/-msse* like any other toolchain.
# $1 = arch (wrapper name), $2 = clang target triple, $3 = prefix, $4 = link-time extra flags
generate_wrappers() {
  local arch="$1" triple="$2" prefix="$3" ldextra="$4"
  local wrap="$arch-w64-mingw32"
  local bindir="$prefix/bin"
  log "${GRE}Generating toolchain wrappers for ${bold}$wrap${c0}${GRE} (target $triple)${c0}\n"

  local entry name mode
  for entry in "clang:--driver-mode=gcc" "clang++:--driver-mode=g++" \
               "gcc:--driver-mode=gcc"   "g++:--driver-mode=g++" \
               "cc:--driver-mode=gcc"    "c++:--driver-mode=g++"; do
    name="${entry%%:*}"; mode="${entry#*:}"
    cat > "$bindir/$wrap-$name" <<EOF
#!/bin/sh
# Auto-generated by $SCRIPTNAME for $wrap
# Resolve clang + sysroot relative to this wrapper so the toolchain is portable.
dir=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
exec "\$dir/clang" $mode --target=$triple --sysroot="\$dir/../$triple" $ldextra "\$@"
EOF
    chmod +x "$bindir/$wrap-$name"
  done

  # binutils-style tools -> LLVM equivalents (relative symlinks in the same dir)
  local tool
  for tool in ar:llvm-ar ranlib:llvm-ranlib nm:llvm-nm strip:llvm-strip \
              objcopy:llvm-objcopy objdump:llvm-objdump dlltool:llvm-dlltool \
              windres:llvm-windres strings:llvm-strings addr2line:llvm-addr2line \
              size:llvm-size readelf:llvm-readobj; do
    ln -sf "${tool#*:}" "$bindir/$wrap-${tool%%:*}"
  done
  # ld -> lld (PE/COFF flavor installs as ld.lld). readelf -> llvm-readobj above
  # gives readelf-style output because the symlink name contains "readelf".
  ln -sf "ld.lld" "$bindir/$wrap-ld"
  # as: LLVM ships no standalone GNU as, so wrap clang's integrated assembler.
  cat > "$bindir/$wrap-as" <<EOF
#!/bin/sh
# Auto-generated by $SCRIPTNAME for $wrap
dir=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
exec "\$dir/clang" --target=$triple -x assembler -c "\$@"
EOF
  chmod +x "$bindir/$wrap-as"
}

# Lay down the Windows toolchain entry points for the Phase 2 deliverable.
# Rather than copy the ~100 MB clang.exe per triple name, compile one tiny shared
# wrapper (assets/src/clang-target-wrapper.c, modelled on llvm-mingw's) and copy it
# to every <triple>-<tool>.exe. At runtime it reads its own argv[0] and execs the
# single real binary next to it: clang (with -target/--driver-mode plus the PE
# subsystem/OS-version defaults) for the drivers, or the matching llvm-* (ld ->
# ld.lld) for the binutils tools. So the prefix ships ONE clang/lld/llvm-* set,
# like upstream. clang locates its sysroot from the triple's sibling dir.
# Deliberately NO -march/SIMD in the wrapper (build-time only) so users keep full
# control of microarchitecture flags.
# $1 = arch, $2 = triple, $3 = prefix, $4 = cross C compiler, $5 = build dir
# Globals used: HERE
generate_wrappers_windows() {
  local arch="$1" triple="$2" prefix="$3" cc="$4" blddir="$5"
  local wrap="$arch-w64-mingw32"
  local bindir="$prefix/bin"
  log "${GRE}Generating Windows toolchain wrappers for ${bold}$wrap${c0}${GRE} (target $triple)${c0}\n"

  # Compile the shared entry-point wrapper once, cross-compiled to a small static
  # Windows .exe. TARGET / EXTRA are baked in as string literals (EXTRA carries
  # the PE subsystem/OS-version link defaults for the clang drivers).
  local wrapper="$blddir/clang-target-wrapper.exe"
  execute "($arch P2): Building toolchain entry-point wrapper" "Building wrapper failed" \
      "$cc" $OPT_FLAGS -s -static -municode \
      -DUNICODE -D_UNICODE -DTARGET="\"$triple\"" \
      "$HERE/assets/src/clang-target-wrapper.c" -o "$wrapper"

  # Stamp the wrapper out under every entry-point name (a few KB each). windres is
  # handled separately below -- it must NOT be the shared wrapper.
  #   - size -> llvm-size, as -> clang -x assembler -c: name-independent, so the
  #     shared wrapper is fine.
  #   - readelf -> llvm-readobj: safe as the shared wrapper too (unlike windres),
  #     because llvm-readobj keys its GNU/readelf output off argv[0] -- which the
  #     wrapper passes through -- not getMainExecutable() like llvm-rc does.
  local name
  for name in clang clang++ gcc g++ cc c++ \
              ar ranlib nm strip objcopy objdump dlltool strings addr2line \
              size readelf as ld; do
    execute "" "Failed to install $wrap-$name.exe" \
        cp -f "$wrapper" "$bindir/$wrap-$name.exe"
  done

  # windres is special: llvm-rc/llvm-windres derives the preprocessor's --target
  # from the triple PREFIX in its OWN program name (isWindres() parses
  # "<triple>-windres"). The shared wrapper execs bare "llvm-windres", and Windows
  # overwrites argv0 with the real module path ("llvm-windres", no prefix), so it
  # falls back to a NORMALIZED default triple (i586-w64-windows-gnu) that clang
  # can't map to the ../<triple> mingw sysroot -> "windows.h: No such file". Ship a
  # real copy of llvm-rc.exe named <triple>-windres.exe so the prefix is in the
  # name: Opts.Triple becomes the literal <triple>, and it finds <triple>-clang
  # (which resolves the sysroot). ~0.5 MB; same trick upstream llvm-mingw uses.
  execute "" "Failed to install $wrap-windres.exe" \
      cp -f "$bindir/llvm-rc.exe" "$bindir/$wrap-windres.exe"
}

# Compute every arch-derived flag the two build phases share, into GLOBALS
# (deliberately not 'local'): triple/wrap, the SIMD baseline, the target/host
# CFLAGS, the PE subsystem version flags, the CRT lib selection and the
# VERSION.txt flag lines. Mirrors the single-phase Linux script's flag block.
# $1 = arch
compute_arch_flags() {
  local arch="$1"

  # Each arch uses its own $arch-w64-mingw32 triple, keeping the sysroot dir,
  # tool names and --host consistent across all four scripts. clang/LLVM treat
  # i386/i486/i586/i686 all as 32-bit x86 (Triple::x86), so i586-w64-mingw32 is a
  # valid target; the CPU floor is pinned by the -march/SIMD flags, not the triple
  # (builtins are named by arch, libclang_rt.builtins-i386.a, either way).
  triple="$arch-w64-mingw32"
  wrap="$arch-w64-mingw32"

  # OPT_FLAGS / STRIP_FLAG are controlled by IS_DEBUG. The test is
  # [ "$IS_DEBUG" = true ], NOT [ "$IS_DEBUG" ]: IS_DEBUG defaults to the
  # string "false", which a plain non-empty test would wrongly treat as true.
  local BASE_FLAGS="-Wno-unused-parameter -Wno-unknown-warning-option -Wno-error"
  OPT_FLAGS="$BASE_FLAGS"
  if [ "$IS_DEBUG" = true ]; then
    OPT_FLAGS+=" -Og -g2 -DDEBUG -D_DEBUG"
    STRIP_FLAG=""
  else
    OPT_FLAGS+=" -O3 -g0 -DNDEBUG -D_NDEBUG"
    STRIP_FLAG="-s"
  fi
  TARGET_LDFLAGS="$STRIP_FLAG"
  if [ "$arch" = "i586" ]; then
    SIMD_FLAGS="-mfpmath=387"
    MARCH=""
    if [ "$USE_MMX" = true ]; then
      SIMD_FLAGS+=" -mmmx -mno-fxsr -mno-sse -mno-sse2"
      MARCH="pentium-mmx"
    else
      SIMD_FLAGS+=" -mno-mmx -mno-fxsr -mno-sse -mno-sse2"
      MARCH="pentium"
    fi
    VERSION_FLAGS="USE_MMX=$USE_MMX"
  elif [ "$arch" = "i686" ]; then
    local sse2=$USE_SSE2 sse3=$USE_SSE3 sse41=$USE_SSE41 sse42=$USE_SSE42
    [ "$sse42" = true ] && sse41=true
    [ "$sse41" = true ] && sse3=true
    [ "$sse3"  = true ] && sse2=true

    SIMD_FLAGS="-mfpmath=sse -mmmx"
    MARCH=""
    if [ "$sse2" = true ]; then
      SIMD_FLAGS+=" -mfxsr -msse2"
      MARCH="pentium4"
    else
      SIMD_FLAGS+=" -mfxsr -msse"
      MARCH="pentium3"
    fi
    if [ "$sse3" = true ]; then
      SIMD_FLAGS+=" -msse3"
      MARCH="prescott"
    fi
    if [ "$sse41" = true ]; then
      SIMD_FLAGS+=" -msse4.1"
      MARCH="core2"
    fi
    if [ "$sse42" = true ]; then
      SIMD_FLAGS+=" -mssse3 -msse4.2"
      MARCH="nehalem"
    fi
    VERSION_FLAGS="USE_SSE2=$sse2
USE_SSE3=$sse3
USE_SSE41=$sse41
USE_SSE42=$sse42"
  elif [ "$arch" = "x86_64" ]; then
    local sse3=$USE_SSE3 sse41=$USE_SSE41 sse42=$USE_SSE42
    local avx=$USE_AVX avx2=$USE_AVX2 avx512=$USE_AVX512
    [ "$avx512" = true ] && avx2=true
    [ "$avx2"   = true ] && avx=true
    [ "$avx"    = true ] && sse42=true
    [ "$sse42"  = true ] && sse41=true
    [ "$sse41"  = true ] && sse3=true

    SIMD_FLAGS="-mfpmath=sse -mmmx -mfxsr -msse -msse2"
    MARCH="x86-64"
    if [ "$sse3" = true ]; then
      SIMD_FLAGS+=" -msse3"
      MARCH="nocona"
    fi
    if [ "$sse41" = true ]; then
      SIMD_FLAGS+=" -msse4.1"
      MARCH="core2"
    fi
    if [ "$sse42" = true ]; then
      SIMD_FLAGS+=" -mssse3 -msse4.2"
      MARCH="x86-64-v2"
    fi
    if [ "$avx" = true ]; then
      SIMD_FLAGS+=" -mavx -maes -mpclmul"
      MARCH="sandybridge"
    fi
    if [ "$avx2" = true ]; then
      SIMD_FLAGS+=" -mavx2 -mfma -mrdrnd -mf16c -mbmi -mbmi2 -ffp-contract=fast"
      TARGET_LDFLAGS+=" -ffp-contract=fast"
      MARCH="x86-64-v3"
    fi
    if [ "$avx512" = true ]; then
      SIMD_FLAGS+=" -mavx512f -mavx512cd -mavx512vl -mavx512bw -mavx512dq"
      MARCH="x86-64-v4"
    fi
    VERSION_FLAGS="USE_SSE3=$sse3
USE_SSE41=$sse41
USE_SSE42=$sse42
USE_AVX=$avx
USE_AVX2=$avx2
USE_AVX512=$avx512"
  else
    error_exit "No matching arch: '$arch'"
  fi
  # -march pins the CPU baseline; SIMD_FLAGS enable/disable the instruction sets.
  SIMD_FLAGS="-march=$MARCH $SIMD_FLAGS"

  # The wrappers no longer bake SIMD, so the autotools runtime builds (CRT,
  # winpthreads, gendef) must carry the arch baseline themselves -- same full
  # OPT+SIMD set the CMake runtime builds use.
  # -DPSAPI_VERSION=1 makes psapi calls (EnumProcessModules, GetProcessMemoryInfo)
  # link against psapi.dll instead of the Win7+ K32* kernel32 forwarders, so the
  # LLVM tools load on XP/2000. Harmless for TUs that don't include <psapi.h>.
  TARGET_CFLAGS="$OPT_FLAGS $SIMD_FLAGS -pipe"
  if (( WIN32_WINNT < 0x0601 )); then
    TARGET_CFLAGS+=" -DPSAPI_VERSION=1"
  else
    TARGET_CFLAGS+=" -DPSAPI_VERSION=2"
  fi
  TARGET_CXXFLAGS="$TARGET_CFLAGS"
  AUTOTOOLS_CFLAGS="$TARGET_CFLAGS"
  # HOST_CFLAGS build the host LLVM tools. In Phase 1 they run on Linux; in
  # Phase 2 they run on the Windows target, so there they use the arch SIMD
  # baseline instead (see build_phase2_windows).
  HOST_CFLAGS="$OPT_FLAGS -mfpmath=sse -msse2 -pipe -D_WIN32_WINNT=$WIN32_WINNT"
  HOST_CXXFLAGS="$HOST_CFLAGS"

  if [ "$arch" = "i586" ] || [ "$arch" = "i686" ]; then
    crt_lib="--enable-lib32 --disable-lib64"
  else
    crt_lib="--enable-lib64 --disable-lib32"
  fi
  VFLAGS=""
  if [ "$VERBOSE" == "1" ]; then
    VFLAGS+=" VERBOSE=1 V=1"
  fi
}

# PHASE 1: build a normal Linux-hosted llvm-mingw toolchain into $2 -- byte-for-
# byte what llvm_linux.sh produces. This is the intermediate that
# drives the Canadian cross: its clang/lld compile Phase 2, its build-tree
# llvm-tblgen/clang-tblgen feed the LLVM cross-build, and its target runtimes
# (compiler-rt/libunwind/libc++/CRT/winpthreads) are reused verbatim by Phase 2.
# Assumes compute_arch_flags() has set the shared globals. $1 = arch, $2 = prefix
build_phase1_linux() {
  local arch="$1"
  local prefix="$2"
  local bld_path="$BLD_PATH/$arch"

  export PATH="$prefix/bin:$PATH"

  # --incremental keeps the existing Phase 1 build tree + prefix so Ninja can do a
  # minimal recompile and install over them; only wipe them on a normal build.
  if [ ! "$INCREMENTAL" ]; then
    remove_path "$bld_path"
    remove_path "$prefix"
  fi

  # CMAKE flags for runtime (target) builds: drive the Phase 1 clang as a cross
  # compiler for $triple.
  local CMAKE_TARGET_ARGS=(
    -DCMAKE_SYSTEM_NAME=Windows
    -DCMAKE_C_COMPILER="$prefix/bin/clang"
    -DCMAKE_CXX_COMPILER="$prefix/bin/clang++"
    -DCMAKE_ASM_COMPILER="$prefix/bin/clang"
    -DCMAKE_C_COMPILER_TARGET="$triple"
    -DCMAKE_CXX_COMPILER_TARGET="$triple"
    -DCMAKE_ASM_COMPILER_TARGET="$triple"
    -DCMAKE_SYSROOT="$prefix/$triple"
    -DCMAKE_AR="$prefix/bin/llvm-ar"
    -DCMAKE_RANLIB="$prefix/bin/llvm-ranlib"
    -DCMAKE_C_FLAGS="$TARGET_CFLAGS"
    -DCMAKE_CXX_FLAGS="$TARGET_CXXFLAGS"
    -DCMAKE_ASM_FLAGS="$TARGET_CFLAGS"
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
  )

  log "${CYA}HOST_CFLAGS    = ${bold}$HOST_CFLAGS ${c0}\n"
  log "${CYA}TARGET_CFLAGS  = ${bold}$TARGET_CFLAGS ${c0}\n"
  log "${CYA}TRIPLE         = ${bold}$triple ${c0}\n"
  log "${CYA}_WIN32_WINNT   = ${bold}${_WIN32_WINNT} ${c0}\n"
  sleep 1

  # 1. LLVM: clang + lld + the llvm-* tools (NATIVE: runs on the build machine).
  #    The build tree (kept until the end) supplies tblgen for Phase 2.
  create_dir "$bld_path/llvm"
  change_dir "$bld_path/llvm"
  # lldb is enabled here (built minimally) so Phase 1's build tree provides the
  # native lldb-tblgen the Phase 2 cross-build needs (as it does for llvm-/clang-
  # tblgen). Phase 1 is the discarded Linux-hosted intermediate, so its own lldb
  # isn't shipped -- only the tblgen matters.
  execute "($arch P1): Configuring LLVM (clang + lld + lldb-tblgen)" "Configuring LLVM failed" \
      cmake -G Ninja "$SRC_PATH/llvm-project/llvm" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix" \
      -DLLVM_ENABLE_PROJECTS="clang;lld;lldb" \
      -DLLVM_TARGETS_TO_BUILD="X86" \
      -DLLDB_ENABLE_PYTHON=OFF \
      -DLLDB_ENABLE_LUA=OFF \
      -DLLDB_ENABLE_LIBEDIT=OFF \
      -DLLDB_ENABLE_CURSES=OFF \
      -DLLDB_ENABLE_LIBXML2=OFF \
      -DLLDB_INCLUDE_TESTS=OFF \
      -DLLVM_ENABLE_ASSERTIONS=OFF \
      -DLLVM_STATIC_LINK_CXX_STDLIB=ON \
      -DLLVM_INCLUDE_TESTS=OFF \
      -DLLVM_INCLUDE_BENCHMARKS=OFF \
      -DLLVM_INCLUDE_EXAMPLES=OFF \
      -DLLVM_ENABLE_ZSTD=OFF \
      -DLLVM_DEFAULT_TARGET_TRIPLE="$triple" \
      -DCLANG_DEFAULT_LINKER=lld \
      -DCLANG_DEFAULT_RTLIB=compiler-rt \
      -DCLANG_DEFAULT_UNWINDLIB=libunwind \
      -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
      -DCMAKE_C_FLAGS="$HOST_CFLAGS" \
      -DCMAKE_CXX_FLAGS="$HOST_CXXFLAGS"
  execute "($arch P1): Building LLVM" "Building LLVM failed" \
      ninja -j $JOB_COUNT
  execute "($arch P1): Installing LLVM" "Installing LLVM failed" \
      ninja install

  generate_wrappers "$arch" "$triple" "$prefix"

  local AUTOTOOLS_TOOLS=(
    "CC=$prefix/bin/$wrap-cc" "CXX=$prefix/bin/$wrap-c++"
    "AR=$prefix/bin/llvm-ar" "RANLIB=$prefix/bin/llvm-ranlib"
    "STRIP=$prefix/bin/llvm-strip" "NM=$prefix/bin/llvm-nm"
    "DLLTOOL=$prefix/bin/llvm-dlltool" "RC=$prefix/bin/llvm-windres"
    "OBJDUMP=$prefix/bin/llvm-objdump"
  )

  # 2. MinGW-w64 headers
  create_dir "$bld_path/mingw-w64-headers"
  change_dir "$bld_path/mingw-w64-headers"
  execute "($arch P1): Configuring MinGW headers" "Configuring MinGW headers failed" \
      "$SRC_PATH/mingw-w64/mingw-w64-headers/configure" --build="$BUILD" \
      --host="$triple" --prefix="$prefix/$triple" \
      --with-default-win32-winnt=$WIN32_WINNT \
      --with-default-msvcrt=$LINKED_RUNTIME \
      "${AUTOTOOLS_TOOLS[@]}" CFLAGS="$AUTOTOOLS_CFLAGS"
  execute "($arch P1): Installing MinGW headers" "Installing MinGW headers failed" \
      make install $VFLAGS

  # 3. MinGW-w64 CRT
  create_dir "$bld_path/mingw-w64-crt"
  change_dir "$bld_path/mingw-w64-crt"
  execute "($arch P1): Configuring MinGW CRT" "Configuring MinGW CRT failed" \
      "$SRC_PATH/mingw-w64/mingw-w64-crt/configure" --build="$BUILD" \
      --host="$triple" --prefix="$prefix/$triple" \
      --with-default-msvcrt=$LINKED_RUNTIME \
      --with-default-win32-winnt=$WIN32_WINNT \
      --with-sysroot="$prefix/$triple" $crt_lib \
      "${AUTOTOOLS_TOOLS[@]}" CFLAGS="$AUTOTOOLS_CFLAGS"
  execute "($arch P1): Building MinGW CRT" "Building MinGW CRT failed" \
      make -j $JOB_COUNT $VFLAGS
  execute "($arch P1): Installing MinGW CRT" "Installing MinGW CRT failed" \
      make install $VFLAGS

  # 4. compiler-rt builtins -> clang resource dir
  local resource_dir
  resource_dir="$("$prefix/bin/clang" -print-resource-dir)"
  create_dir "$bld_path/compiler-rt"
  change_dir "$bld_path/compiler-rt"
  execute "($arch P1): Configuring compiler-rt" "Configuring compiler-rt failed" \
      cmake -G Ninja "$SRC_PATH/llvm-project/compiler-rt" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$resource_dir" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      "${CMAKE_TARGET_ARGS[@]}" \
      -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
      -DCOMPILER_RT_BUILD_BUILTINS=ON \
      -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
      -DCOMPILER_RT_BUILD_XRAY=OFF \
      -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DCOMPILER_RT_BUILD_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
      -DCOMPILER_RT_BUILD_ORC=OFF
  execute "($arch P1): Building compiler-rt" "Building compiler-rt failed" \
      ninja -j $JOB_COUNT
  execute "($arch P1): Installing compiler-rt" "Installing compiler-rt failed" \
      ninja install

  # 5. winpthreads
  if [ "$ENABLE_THREADS" ]; then
    create_dir "$bld_path/mingw-w64-winpthreads"
    change_dir "$bld_path/mingw-w64-winpthreads"
    execute "($arch P1): Configuring winpthreads" "Configuring winpthreads failed" \
        "$SRC_PATH/mingw-w64/mingw-w64-libraries/winpthreads/configure" \
        --build="$BUILD" --host="$triple" --disable-shared \
        --enable-static --prefix="$prefix/$triple" \
        "${AUTOTOOLS_TOOLS[@]}" CFLAGS="$AUTOTOOLS_CFLAGS"
    execute "($arch P1): Building winpthreads" "Building winpthreads failed" \
        make -j $JOB_COUNT $VFLAGS
    execute "($arch P1): Installing winpthreads" "Installing winpthreads failed" \
        make install $VFLAGS
  fi

  # 6. LLVM runtimes: libunwind + libc++abi + libc++
  #
  # libc++ is built BOTH static (libc++.a, for self-contained target programs)
  # AND shared (libc++.dll). The shared build is required for correctness of the
  # Phase 2 LLVM_LINK_LLVM_DYLIB toolchain: with static libc++, each of
  # libLLVM-*.dll and libclang-cpp.dll embeds its own copy of libc++, giving
  # each dylib a distinct std::error_code category singleton. std::error_code
  # comparison tests the category by ADDRESS, so a "file not found" produced in
  # libLLVM's Support code never compares equal to llvm::errc::no_such_file...
  # when checked in libclang's HeaderSearch -- clang then treats a missing entry
  # in one -I/-isystem dir as a fatal "cannot open file" instead of falling
  # through to the next dir, breaking every compile with a user -I. A single
  # shared libc++.dll gives all modules one category singleton. libc++abi and
  # libunwind stay static (folded into libc++.dll) so it is self-contained.
  #
  # The LIB*_HAS_{ATOMIC,DL,C}_LIB=OFF overrides below are required for the
  # SHARED build: libc++/libunwind/libc++abi config-ix.cmake only special-case
  # `WIN32 AND NOT MINGW`, so a mingw target falls through to the generic Unix
  # branch and mis-detects -latomic/-ldl/-lc (none of which exist on mingw --
  # atomics are compiler builtins, dl is in kernel32, libc is msvcrt). A static
  # .a never links so it slid by, but the shared libc++.dll link fails on the
  # missing libs. Forcing them off matches how mingw actually provides them.
  local LIBCXX_THREADS
  if [ "$ENABLE_THREADS" ]; then
    LIBCXX_THREADS="-DLIBCXX_ENABLE_THREADS=ON -DLIBCXXABI_ENABLE_THREADS=ON -DLIBUNWIND_ENABLE_THREADS=ON -DLIBCXX_HAS_PTHREAD_API=ON"
  else
    LIBCXX_THREADS="-DLIBCXX_ENABLE_THREADS=OFF -DLIBCXXABI_ENABLE_THREADS=OFF -DLIBUNWIND_ENABLE_THREADS=OFF"
  fi
  create_dir "$bld_path/runtimes"
  change_dir "$bld_path/runtimes"
  execute "($arch P1): Configuring libunwind/libc++abi/libc++" "Configuring runtimes failed" \
      cmake -G Ninja "$SRC_PATH/llvm-project/runtimes" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix/$triple" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      "${CMAKE_TARGET_ARGS[@]}" \
      -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
      -DLLVM_INCLUDE_TESTS=OFF \
      -DLIBUNWIND_INCLUDE_TESTS=OFF \
      -DLIBCXXABI_INCLUDE_TESTS=OFF \
      -DLIBCXX_INCLUDE_TESTS=OFF \
      -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
      -DLIBUNWIND_USE_COMPILER_RT=ON \
      -DLIBUNWIND_ENABLE_SHARED=OFF \
      -DLIBUNWIND_ENABLE_STATIC=ON \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
      -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
      -DLIBCXXABI_ENABLE_SHARED=OFF \
      -DLIBCXXABI_ENABLE_STATIC=ON \
      -DLIBCXX_USE_COMPILER_RT=ON \
      -DLIBCXX_CXX_ABI=libcxxabi \
      -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
      -DLIBCXX_ENABLE_SHARED=ON \
      -DLIBCXX_ENABLE_STATIC=ON \
      -DLIBCXX_ENABLE_EXCEPTIONS=ON \
      -DLIBCXX_HAS_ATOMIC_LIB=OFF \
      -DLIBUNWIND_HAS_DL_LIB=OFF \
      -DLIBUNWIND_HAS_C_LIB=OFF \
      -DLIBCXXABI_HAS_DL_LIB=OFF \
      -DLIBCXXABI_HAS_C_LIB=OFF \
      $LIBCXX_THREADS
  execute "($arch P1): Building libunwind/libc++abi/libc++" "Building runtimes failed" \
      ninja -j $JOB_COUNT
  execute "($arch P1): Installing libunwind/libc++abi/libc++" "Installing runtimes failed" \
      ninja install

  log "${GRE}Phase 1 (Linux-hosted) toolchain for $arch ready.${c0}\n"
}

# PHASE 2: cross-compile the Windows-hosted toolchain into $prefix using the
# Phase 1 toolchain at $3. clang/lld/llvm-* are rebuilt as static Windows .exe;
# the target runtimes + compiler-rt are copied from Phase 1 (identical PE bits);
# gendef is Canadian-crossed to gendef.exe; wrappers + clang config are laid down.
# Assumes compute_arch_flags() has set the shared globals.
# $1 = arch, $2 = prefix (deliverable), $3 = Phase 1 prefix
build_phase2_windows() {
  local arch="$1"
  local prefix="$2"
  local p1="$3"
  local bld_path="$BLD_PATH/$arch"

  # Do NOT wipe $bld_path here: Phase 1's llvm/ build tree (with the native
  # tblgens) still lives there and the LLVM cross-build needs it.
  # --clang-format adds to the existing prefix, so don't wipe it in that mode.
  if [ ! "$PREFIX" ] && [ ! "$CLANG_FORMAT_ONLY" ] && [ ! "$INCREMENTAL" ]; then
    remove_path "$prefix"
  fi

  local native_tools="$bld_path/llvm/bin"
  for t in llvm-tblgen clang-tblgen; do
    if [ ! -x "$native_tools/$t" ]; then
      error_exit "Phase 2: native $t not found at '$native_tools' (Phase 1 build tree missing? do not pass --keep-artifacts-less runs that wipe bld between phases)"
    fi
  done

  log "${CYA}NATIVE_TOOLS   = ${bold}$native_tools ${c0}\n"
  log "${CYA}CROSS CC       = ${bold}$p1/bin/clang (--target=$triple) ${c0}\n"
  sleep 1

  # 1. Cross-compile LLVM (clang/lld/llvm-* as Windows .exe). The Phase 1 clang
  #    is the cross compiler; LLVM_NATIVE_TOOL_DIR points at Phase 1's build-tree
  #    tblgens (which must run on the build machine). Static link so the .exe
  #    carry no libc++/libunwind/winpthread DLL deps. Built with the arch SIMD
  #    baseline so clang.exe itself runs on the same CPU floor it targets.
  #    -pthread is required: CMake assumes Win32 native threads for a Windows
  #    target and links no thread lib, but our libc++/LLVM use pthreads, so we
  #    force clang to pull in winpthreads (-lpthread) at compile and link time.
  #    psapi: LLVM Support only links it under if(MSVC OR MINGW), but CMake sees
  #    clang-with-a-mingw-target as neither, so we add it -- via
  #    CMAKE_*_STANDARD_LIBRARIES so -lpsapi lands at the END of the link line
  #    (after the objects that reference EnumProcessModules/GetProcessMemoryInfo),
  #    pulling ONLY those two symbols. An earlier --whole-archive force-linked ALL
  #    of psapi, including Vista+ exports (EnumProcessModulesEx/QueryWorkingSetEx/
  #    GetWsChangesEx) that XP's psapi.dll lacks -> the tools failed to LOAD on XP.
  #    libunwind's own EnumProcessModules is resolved dynamically instead.
  #    ole32: lldb's HostInfoWindows.cpp calls CoInitializeEx/CoUninitialize, but
  #    lldb's CMake never links ole32 (MSVC auto-links COM via #pragma comment,
  #    which ld.lld in mingw mode ignores). Added the same end-of-line way; it's
  #    only pulled by objects that reference it (i.e. liblldb), and COM is Vista+-
  #    safe anyway since lldb itself is a Vista-floor component.
  create_dir "$bld_path/llvm-win"
  change_dir "$bld_path/llvm-win"
  # Toolchain-only install set, applied via `ninja install-distribution` below:
  # clang/lld + the binutils-style llvm-* tools the wrappers symlink to, plus
  # clang-format/clang-scan-deps and the clang resource headers. Everything else
  # the build produces -- the LLVM dev/test tools (opt, llc, clang-repl,
  # clang-check, ...), the static dev libs (~330MB) and the LLVM/clang headers
  # (~70MB) -- is left uninstalled, taking the deliverable toolchain from ~2GB to
  # a few hundred MB. The target runtimes/compiler-rt are copied in from Phase 1
  # afterwards, so they are unaffected. (clang++/clang-cl ride with the clang
  # component; llvm-ranlib/llvm-lib/llvm-dlltool/llvm-strip/llvm-addr2line are
  # symlinks listed by their own name.) Only Phase 2 (the shipped, Windows-hosted
  # toolchain) is trimmed; Phase 1 stays a full install since it is the bootstrap
  # compiler used to cross-build Phase 2.
  #
  # ASYMMETRY: unlike the Linux-hosted toolchain (llvm_linux.sh), this list
  # has NO llvm-mt. llvm-mt (the Windows manifest tool) needs libxml2, which is
  # OFF here (LLVM_ENABLE_LIBXML2=OFF below): the host's libxml2 is a Linux .so
  # and can't link into a static Windows .exe, and cross-building a static,
  # XP-safe libxml2 isn't worth it for one rarely-used tool. lld still embeds
  # manifests without it; only multi-manifest *merging* is lost.
  # Shared-library build (matches upstream llvm-mingw): LLVM_LINK_LLVM_DYLIB=ON
  # (below) places all LLVM/clang code into libLLVM*.dll + libclang-cpp.dll once,
  # so every tool becomes a thin stub linking them -- cutting the toolchain to a
  # fraction of the static size. The leading LLVM and clang-cpp components install
  # those two DLLs; without them, install-distribution would ship stub tools with
  # no library to load.
  #
  # NOTE: the linker flags below intentionally OMIT -static. With the shared
  # dylib build, libc++ must be linked SHARED (as libc++.dll, built in Phase 1)
  # so libLLVM-*.dll, libclang-cpp.dll and every tool share ONE libc++ -- hence
  # one std::error_code category singleton (see the runtimes comment above; a
  # per-module libc++ makes clang's header-search fall-through fatally misfire).
  # Only libc++ has a shared variant in the sysroot (libunwind/libc++abi/
  # winpthreads/compiler-rt are all static-only), so dropping -static makes
  # ONLY libc++ dynamic; everything else stays statically linked as before.
  local llvm_dist="LLVM;clang-cpp;clang;clang-resource-headers;clang-format;clang-scan-deps;clang-tidy;lld;llvm-ar;llvm-ranlib;llvm-lib;llvm-dlltool;llvm-nm;llvm-objcopy;llvm-strip;llvm-objdump;llvm-windres;llvm-rc;llvm-cvtres;llvm-addr2line;llvm-symbolizer;llvm-strings;llvm-cxxfilt;llvm-readobj;llvm-size;llvm-dwarfdump;llvm-profdata;llvm-cov;lldb;liblldb"
  execute "($arch P2): Configuring Windows-hosted LLVM" "Configuring Windows LLVM failed" \
      cmake -G Ninja "$SRC_PATH/llvm-project/llvm" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix" \
      -DCMAKE_SYSTEM_NAME=Windows \
      -DCMAKE_C_COMPILER="$p1/bin/clang" \
      -DCMAKE_CXX_COMPILER="$p1/bin/clang++" \
      -DCMAKE_C_COMPILER_TARGET="$triple" \
      -DCMAKE_CXX_COMPILER_TARGET="$triple" \
      -DCMAKE_SYSROOT="$p1/$triple" \
      -DCMAKE_AR="$p1/bin/llvm-ar" \
      -DCMAKE_RANLIB="$p1/bin/llvm-ranlib" \
      -DCMAKE_RC_COMPILER="$p1/bin/llvm-windres" \
      -DCMAKE_FIND_ROOT_PATH="$p1/$triple" \
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
      -DLLVM_NATIVE_TOOL_DIR="$native_tools" \
      -DLLVM_TABLEGEN="$native_tools/llvm-tblgen" \
      -DCLANG_TABLEGEN="$native_tools/clang-tblgen" \
      -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra;lld;lldb;polly" \
      -DLLVM_TARGETS_TO_BUILD="X86" \
      -DLLVM_POLLY_LINK_INTO_TOOLS=ON \
      -DLLDB_TABLEGEN="$native_tools/lldb-tblgen" \
      -DLLDB_ENABLE_PYTHON=OFF \
      -DLLDB_ENABLE_LUA=OFF \
      -DLLDB_ENABLE_LIBEDIT=OFF \
      -DLLDB_ENABLE_CURSES=OFF \
      -DLLDB_ENABLE_LIBXML2=OFF \
      -DLLDB_INCLUDE_TESTS=OFF \
      -DLLVM_HOST_TRIPLE="$triple" \
      -DLLVM_DEFAULT_TARGET_TRIPLE="$triple" \
      -DLLVM_ENABLE_ASSERTIONS=OFF \
      -DLLVM_INCLUDE_TESTS=OFF \
      -DLLVM_INCLUDE_BENCHMARKS=OFF \
      -DLLVM_INCLUDE_EXAMPLES=OFF \
      -DLLVM_LINK_LLVM_DYLIB=ON \
      -DLLVM_DISTRIBUTION_COMPONENTS="$llvm_dist" \
      -DLLVM_ENABLE_ZSTD=OFF \
      -DLLVM_ENABLE_ZLIB=OFF \
      -DLLVM_ENABLE_LIBXML2=OFF \
      -DLLVM_ENABLE_TERMINFO=OFF \
      -DCLANG_DEFAULT_LINKER=lld \
      -DCLANG_DEFAULT_RTLIB=compiler-rt \
      -DCLANG_DEFAULT_UNWINDLIB=libunwind \
      -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
      -DCMAKE_C_FLAGS="$TARGET_CFLAGS -pthread -D_WIN32_WINNT=$WIN32_WINNT" \
      -DCMAKE_CXX_FLAGS="$TARGET_CXXFLAGS -pthread -D_WIN32_WINNT=$WIN32_WINNT" \
      -DCMAKE_EXE_LINKER_FLAGS="-pthread $STRIP_FLAG" \
      -DCMAKE_SHARED_LINKER_FLAGS="-pthread $STRIP_FLAG" \
      -DCMAKE_MODULE_LINKER_FLAGS="-pthread $STRIP_FLAG" \
      -DCMAKE_C_STANDARD_LIBRARIES="-lpsapi -lole32" \
      -DCMAKE_CXX_STANDARD_LIBRARIES="-lpsapi -lole32"

  # --clang-format: build ONLY clang-format.exe (cross-compiled via Phase 1's
  # clang) and drop it into the prefix's bin/, then stop -- skips the full LLVM
  # cross, the sysroot copy, gendef and the wrappers. (Phase 1 is reused, see build().)
  if [ "$CLANG_FORMAT_ONLY" ]; then
    execute "($arch P2): Building clang-format.exe" "Building clang-format failed" \
        ninja -j $JOB_COUNT clang-format
    create_dir "$prefix/bin"
    execute "($arch P2): Installing clang-format.exe" "Installing clang-format failed" \
        cp -fv "$bld_path/llvm-win/bin/clang-format.exe" "$prefix/bin"
    log "${GRE}Done building clang-format.exe for arch ${CYA}$arch ${c0}\n"
    return 0
  fi

  # Build only the distribution set (what install-distribution ships) instead of
  # everything: clang-tools-extra is enabled for clang-tidy, and building just the
  # distribution keeps the rest of it -- clangd especially -- from cross-building
  # for nothing. clang-tidy's native codegen helper (clang-tidy-confusable-chars-
  # gen) isn't in $native_tools, so LLVM's setup_host_tool auto-builds that one
  # tool natively on demand (Phase 1 stays a plain clang;lld;lldb build).
  execute "($arch P2): Building Windows-hosted LLVM" "Building Windows LLVM failed" \
      ninja -j $JOB_COUNT distribution
  execute "($arch P2): Installing Windows-hosted LLVM" "Installing Windows LLVM failed" \
      ninja install-distribution

  # install-distribution also drops non-binary helper scripts (git-clang-format +
  # its .bat, run-clang-tidy) into bin/. This toolchain ships only real binaries,
  # so strip the Python/batch clutter.
  rm -f "$prefix/bin/"git-clang-format "$prefix/bin/"git-clang-format.bat \
        "$prefix/bin/"run-clang-tidy "$prefix/bin/"clang-tidy-diff.py

  # clang-format.exe ships in the toolchain bin/ (next to gendef.exe) so the
  # toolchain can also lint C++ projects; `ninja` already built it -- copy it in.
  execute "($arch P2): Installing clang-format.exe" "Installing clang-format failed" \
      cp -fv "$bld_path/llvm-win/bin/clang-format.exe" "$prefix/bin"

  # 2. Reuse Phase 1's target runtimes -- identical PE bits regardless of where
  #    the compiler runs: the sysroot ($triple: headers + CRT + libc++/libunwind/
  #    winpthreads) and the compiler-rt builtins in the clang resource dir.
  if [ "$INCREMENTAL" ]; then
    # The prefix is kept, so its sysroot/builtins already exist -- a plain cp -a
    # would nest them. rsync --delete makes an unchanged sysroot near-free while a
    # changed one (e.g. a libcxx/libunwind patch rebuilt in Phase 1) still lands.
    execute "($arch P2): Syncing target sysroot from Phase 1" "Failed to sync sysroot" \
        rsync -a --delete "$p1/$triple/" "$prefix/$triple/"
    execute "($arch P2): Syncing compiler-rt builtins from Phase 1" "Failed to sync builtins" \
        rsync -a --delete "$p1/lib/clang/" "$prefix/lib/clang/"
  else
    execute "($arch P2): Copying target sysroot from Phase 1" "Failed to copy sysroot" \
        cp -a "$p1/$triple" "$prefix/"
    execute "($arch P2): Copying compiler-rt builtins from Phase 1" "Failed to copy builtins" \
        cp -a "$p1/lib/clang" "$prefix/lib/"
  fi

  # 2b. Ship the shared libc++.dll next to the host binaries (clang.exe,
  #     libLLVM-*.dll, libclang-cpp.dll, lld, llvm-*), so every module resolves
  #     libc++ from the SAME DLL -> one std::error_code category singleton (see
  #     the Phase 1 runtimes note). The host binaries were linked against it in
  #     step 1; Windows loads it from the exe's own directory (bin/).
  execute "($arch P2): Installing shared libc++.dll into host bin/" "Failed to install libc++.dll" \
      cp -av "$prefix/$triple/bin/"libc++*.dll "$prefix/bin/"
  # Keep TARGET programs self-contained: drop the shared import lib (and the now-
  # unreferenced sysroot DLL) so the deployed sysroot's default -lc++ resolves to
  # the static libc++.a -- target .exe/.dll stay dependency-free for XP, exactly
  # as before. (Only the host toolchain uses the shared libc++.dll, from bin/.)
  rm -f "$prefix/$triple/lib/"libc++*.dll.a "$prefix/$triple/bin/"libc++*.dll

  # 3. gendef + the auxiliary mingw-w64 host tools (genidl, genpeimg, widl),
  #    Canadian-crossed to .exe via the Phase 1 wrapper and dropped into bin/.
  #    gendef, genidl and genpeimg are plain tools. widl (the Wine IDL compiler)
  #    restricts its target to *-mingw32 and bakes a default IDL include dir;
  #    pointing its --prefix at the real toolchain prefix makes that dir a
  #    relocatable "../$triple/include" that widl re-derives from its own exe at
  #    runtime (via GetModuleFileNameA), so it survives the toolchain being moved.
  local _tool _cfg
  for _tool in gendef genidl genpeimg widl; do
    if [ "$_tool" = widl ]; then
      _cfg="--host=$triple --target=$triple --prefix=$prefix --with-widl-includedir=$prefix/$triple/include"
    else
      _cfg="--host=$triple --prefix=$prefix/$triple"
    fi
    create_dir "$bld_path/$_tool-win"
    change_dir "$bld_path/$_tool-win"
    execute "($arch P2): Configuring MinGW $_tool (Windows)" "Configuring $_tool failed" \
        "$SRC_PATH/mingw-w64/mingw-w64-tools/$_tool/configure" --build="$BUILD" \
        $_cfg \
        "CC=$p1/bin/$wrap-cc" CFLAGS="$AUTOTOOLS_CFLAGS"
    execute "($arch P2): Building MinGW $_tool (Windows)" "Building $_tool failed" \
        make -j $JOB_COUNT $VFLAGS
    execute "($arch P2): Installing MinGW $_tool (Windows)" "Installing $_tool failed" \
        cp -v "$_tool.exe" "$prefix/bin"
  done

  # 3b. GNU make -> mingw32-make.exe (+ a make.exe alias), Canadian-crossed via
  #     the Phase 1 wrapper like the tools above, so the Windows toolchain is
  #     self-contained (Windows ships no make). -std=gnu17: make 4.4.1's bundled
  #     gnulib has K&R decls that clash with a C23-default () == (void).
  create_dir "$bld_path/make-win"
  change_dir "$bld_path/make-win"
  execute "($arch P2): Configuring GNU make (Windows)" "Configuring make failed" \
      "$SRC_PATH/make/configure" --build="$BUILD" --host="$triple" \
      --disable-nls --disable-dependency-tracking \
      "CC=$p1/bin/$wrap-cc" CFLAGS="$AUTOTOOLS_CFLAGS -std=gnu17"
  execute "($arch P2): Building GNU make (Windows)" "Building make failed" \
      make -j $JOB_COUNT $VFLAGS
  execute "($arch P2): Installing mingw32-make.exe + make.exe" "Installing make failed" \
      cp -v "make.exe" "$prefix/bin/mingw32-make.exe"
  cp -f "$prefix/bin/mingw32-make.exe" "$prefix/bin/make.exe"

  # 4. Windows toolchain wrappers + clang config, then the extra MSVC-compat
  #    headers and the version manifest.
  generate_wrappers_windows "$arch" "$triple" "$prefix" "$p1/bin/$wrap-cc" "$bld_path"

  # Host-side utilities from assets/src -> bin/ as Windows .exe, like gendef.exe.
  # Built LAST with the Phase 1 cross compiler (wrapper) + the arch SIMD baseline
  # (AUTOTOOLS_CFLAGS, so they run on the target CPU floor), -municode (they use a
  # Unicode wmain entry), capped at C17 (-std=gnu17) for gcc 11.
  local _t _n _src _xf
  for _t in "peports:peports.c" "pkg-config:pkg-config.c" "xxd:rexxd.c" "uuidgen:uuidgen.c"; do
    _n=${_t%%:*}; _src=${_t#*:}; _xf=""; [ "$_n" = xxd ] && _xf="-funroll-loops"
    execute "($arch P2): Building host tool $_n.exe" "Building $_n failed" \
        "$p1/bin/$wrap-cc" -municode $AUTOTOOLS_CFLAGS -std=gnu17 $_xf -s "$HERE/assets/src/$_src" -o "$prefix/bin/$_n.exe"
  done

  # mingw-ver.exe -- one binary that reports the whole toolchain at a glance.
  # C++ with a narrow main (no -municode). Compiled with the Phase 1 wrapper, so
  # its own macros already describe this toolchain; we additionally inject the
  # facts the headers don't expose (git refs, versions, config) as -D string
  # literals, and read the SIMD baseline + exception model from the compiler's
  # predefined macros for this arch's baseline.
  local _mv_cc _mv_bits _mv_thr _mv_mingw _mv_cref _mv_cfg _mv_pd _mv_simd _mv_exc
  _mv_cc=$("$p1/bin/$wrap-cc" --version 2>/dev/null | head -1)
  _mv_mingw=$(git_ref "$SRC_PATH/mingw-w64" "$MINGW_W64_BRANCH")
  _mv_cref=$(git_ref "$SRC_PATH/llvm-project" "$LLVM_BRANCH")
  _mv_cfg=$(grep -m1 '^timestamp=' "$SRC_PATH/config.guess" | cut -d"'" -f2)
  [ "$arch" = x86_64 ] && _mv_bits="64-bit" || _mv_bits="32-bit"
  [ "$ENABLE_THREADS" ] && _mv_thr="winpthreads (posix)" || _mv_thr="none"
  _mv_pd=$(printf '' | "$p1/bin/$wrap-cc" $SIMD_FLAGS ${MARCH:+-march=$MARCH} -dM -E - 2>/dev/null)
  case "$_mv_pd" in *__AVX512F__*) _mv_simd="AVX-512";; *__AVX2__*) _mv_simd="AVX2";; *__AVX__*) _mv_simd="AVX";; *__SSE4_2__*) _mv_simd="SSE4.2";; *__SSE4_1__*) _mv_simd="SSE4.1";; *__SSSE3__*) _mv_simd="SSSE3";; *__SSE3__*) _mv_simd="SSE3";; *__SSE2__*) _mv_simd="SSE2";; *__SSE__*) _mv_simd="SSE";; *__MMX__*) _mv_simd="MMX";; *) _mv_simd="x87 (no SIMD)";; esac
  case "$_mv_pd" in *__SEH__*) _mv_exc="SEH";; *__USING_SJLJ_EXCEPTIONS__*) _mv_exc="SJLJ";; *) _mv_exc="DWARF (DW2)";; esac
  execute "($arch P2): Building host tool mingw-ver.exe" "Building mingw-ver failed" \
      "$p1/bin/$wrap-c++" $AUTOTOOLS_CFLAGS -std=gnu++17 -s \
      -DMV_KIND='"LLVM/Clang"' -DMV_STDLIB='"libc++"' -DMV_RTLIB='"compiler-rt + libunwind"' \
      -DMV_COMPILER="\"$_mv_cc\"" \
      -DMV_MINGW_REF="\"$_mv_mingw\"" -DMV_COMPILER_REF="\"$_mv_cref\"" \
      -DMV_TOOLCHAIN_VER="\"$SCRIPTVER\"" -DMV_CONFIG_GUESS="\"$_mv_cfg\"" \
      -DMV_ARCH="\"$arch\"" -DMV_TRIPLE="\"$triple\"" \
      -DMV_THREADS="\"$_mv_thr\"" -DMV_RUNTIME="\"$LINKED_RUNTIME\"" \
      -DMV_BITS="\"$_mv_bits\"" -DMV_WIN32_WINNT=$WIN32_WINNT \
      -DMV_SIMD="\"$_mv_simd\"" -DMV_EXCEPTIONS="\"$_mv_exc\"" \
      "$HERE/assets/src/mingw-ver.cc" -o "$prefix/bin/mingw-ver.exe"

  copy_extra_files "$triple" "$prefix"
  # LLVM installs its multicall aliases (ld.lld, lld-link, llvm-windres, clang++,
  # ...) as Unix symlinks; Windows can't follow them, so turn them into real files.
  flatten_install_symlinks "$prefix"
  write_version_file "$arch" "$prefix" "Windows" "$VERSION_FLAGS"
  log "${GRE}Done building Windows-hosted toolchain for ${CYA}$arch ${c0}\n"
}

# Orchestrate a Windows-hosted toolchain for $arch via the two-phase Canadian
# cross. $1 = arch, $2 = prefix (final Windows-hosted deliverable).
# --incremental helper: reset the (kept) git source trees to pristine and re-apply
# every patch, so edits to a .patch take effect -- but keep the mtime of any file
# whose re-patched content is byte-identical to before, so Ninja recompiles only
# the files a patch actually changed (a one-line patch tweak rebuilds one TU, not
# every patched file). Needs the sources to already exist (a prior --keep-artifacts
# or --incremental build). Only the LLVM/mingw SOURCE is reset; build trees and the
# install prefix are kept so Ninja resumes where it left off.
reapply_patches_incremental() {
  log "${GRE}Incremental: resetting sources + re-applying patches...${c0}\n"
  local manifest; manifest="$(mktemp)"
  local rel repo f oh om
  # The git source trees to reset -- whatever download_sources cloned.
  local repos=()
  for repo in "$SRC_PATH"/*/.git; do
    [ -d "$repo" ] && repos+=("${repo%/.git}")
  done
  # 1. hash + mtime of every file the current patches touch, before the reset.
  for f in "$HERE"/patches/*/*.patch; do
    sed -n 's|^+++ b/\([^[:space:]]*\).*|\1|p' "$f"
  done | sort -u | while read -r rel; do
    for repo in "${repos[@]}"; do
      f="$repo/$rel"
      [ -f "$f" ] && printf '%s\t%s\t%s\n' \
        "$f" "$(sha1sum < "$f" | cut -d' ' -f1)" "$(stat -c %Y "$f")"
    done
  done > "$manifest"
  # 2. reset each git tree to pristine (undo patch edits, drop .rej / added files).
  for repo in "${repos[@]}"; do
    execute "" "Failed to reset $(basename "$repo") to pristine" \
        git -C "$repo" checkout -- .
    git -C "$repo" clean -fdq
  done
  rm -f "$SRC_PATH/patches/applied_patches"
  # 3. re-apply (copies the current patches in, applies them, re-touches sentinel).
  apply_patches || error_exit "Failed to re-apply patches"
  # 4. restore mtime wherever the re-patched content is unchanged, so the build skips it.
  while IFS=$'\t' read -r f oh om; do
    [ -f "$f" ] && [ "$(sha1sum < "$f" | cut -d' ' -f1)" = "$oh" ] && touch -d "@$om" "$f"
  done < "$manifest"
  rm -f "$manifest"
}

build() {
  if [ "$WIN32_WINNT" != "0" ]; then
    export _WIN32_WINNT=$WIN32_WINNT
  else
    error_exit "WIN32_WINNT should not be 0!"
  fi

  if [[ -f "$SRC_PATH/patches/applied_patches" ]]; then
    # Only report this on a genuine --cached-sources re-run; during a fresh
    # multi-arch build the sentinel just carries between archs silently.
    [ "$CACHED_SOURCES" ] && printf "${YEL}Already applied patches.${c0}\n"
  else
    apply_patches || error_exit "Failed to apply patches"
  fi

  log "${GRE}Starting build using $JOB_COUNT jobs.${c0}\n"

  local arch="$1"
  local prefix="$2"
  shift 2

  compute_arch_flags "$arch"

  local linux_prefix="$ROOT_PATH/linux-cross/$arch"
  # Phase 2 cross-builds clang-format.exe with Phase 1's clang + native tblgens, so
  # --clang-format still needs Phase 1. Reuse it if its toolchain AND build tree are
  # still present (e.g. a prior --keep-artifacts run); otherwise build Phase 1.
  if [ "$CLANG_FORMAT_ONLY" ] && [ -x "$linux_prefix/bin/clang" ] \
     && [ -x "$BLD_PATH/$arch/llvm/bin/llvm-tblgen" ]; then
    log "${YEL}=== ($arch) --clang-format: reusing existing Phase 1 toolchain + build tree ===${c0}\n"
  else
    log "${GRE}=== ($arch) Starting Phase 1: Linux-hosted cross toolchain ===${c0}\n"
    build_phase1_linux "$arch" "$linux_prefix"
  fi

  log "${GRE}=== ($arch) Starting Phase 2: Windows-hosted toolchain ===${c0}\n"
  build_phase2_windows "$arch" "$prefix" "$linux_prefix"
}

# Zip an arch's install prefix into <root>/<pkgname>.zip. The 64-bit build is
# packaged as x64.zip even though its prefix dir is x86_64; to give the archive a
# matching top-level folder we stage a hardlink tree (cheap, no extra disk, and
# leaves the original prefix untouched).
package_arch() {
  local arch="$1" pkgname="$2"
  local dir="$ROOT_PATH/$arch"
  [ -d "$dir" ] || error_exit "Cannot package '$arch': '$dir' not found"

  change_dir "$ROOT_PATH"
  rm -f "$pkgname.zip"
  if [ "$arch" = "$pkgname" ]; then
    execute "Packaging ${pkgname}.zip..." "Failed to create ${pkgname}.zip" \
        zip -r -q "$pkgname.zip" "$arch"
  else
    remove_path "$pkgname"
    execute "Running cp -al" "Failed to stage '$pkgname'" \
        cp -al "$arch" "$pkgname"
    execute "Packaging ${pkgname}.zip..." "Failed to create ${pkgname}.zip" \
        zip -r -q "$pkgname.zip" "$pkgname"
    remove_path "$pkgname"
  fi
}

install_deps() {
  if ! command -v apt-get >/dev/null; then
    error_exit "--deps only supports apt-based systems (Ubuntu/Debian); install the prerequisites manually"
  fi
  # use sudo only when not already root (e.g. plain CI containers lack sudo)
  local sudo=""
  [ "$(id -u)" -ne 0 ] && sudo="sudo"

  printf "${GRE}Installing dependencies for $SCRIPTNAME...${c0}\n"
  # build-essential + cmake + ninja build LLVM; python3 is required by the LLVM
  # build; the rest provide the tools the missing-executable check requires,
  # plus zip for --package. clang/lld can bootstrap LLVM faster than g++ but
  # build-essential's g++ is sufficient. libxml2-dev isn't used by this script
  # today (the Windows-hosted toolchain keeps LLVM_ENABLE_LIBXML2=OFF and omits
  # llvm-mt -- see the llvm_dist note in build()); it's installed for parity with
  # llvm_linux.sh and in case a future static/XP-safe libxml2 path enables
  # llvm-mt here too.
  $sudo apt-get update || error_exit "apt-get update failed"
  $sudo apt-get install -y \
      build-essential cmake ninja-build python3 git curl zip bzip2 diffutils \
      libxml2-dev \
      || error_exit "Failed to install dependencies"
  printf "${GRE}Done installing dependencies!${c0}\n"
}

while :; do
  case $1 in
    -h|--help)
        show_help
        exit 0
        ;;
    --version)
        show_version
        ;;
    --deps)
        install_deps
        exit 0
        ;;
    -v|--verbose)
        VERBOSE=1
        ;;
    --debug)
        IS_DEBUG=true
        ;;
    -j|--jobs)
        if [ "$2" ]; then
          JOB_COUNT=$2
          shift
        else
          arg_error "'--jobs' requires a non-empty option argument"
        fi
        ;;
    --prefix)
        if [ "$2" ]; then
          PREFIX="$2"
          shift
        else
          arg_error "'--prefix' requires a non-empty option argument"
        fi
        ;;
    --prefix=?*)
        PREFIX=${1#*=}
        ;;
    --prefix=)
        arg_error "'--prefix' requires a non-empty option argument"
        ;;
    --root)
        if [ "$2" ]; then
          ROOT_PATH_ARG="$2"
          shift
        else
          arg_error "'--root' requires a non-empty option argument"
        fi
        ;;
    --root=?*)
        ROOT_PATH_ARG="${1#*=}"
        ;;
    --root=)
        arg_error "'--root' requires a non-empty option argument"
        ;;
    --keep-artifacts)
        KEEP_ARTIFACTS=1
        ;;
    --clean)
        CLEAN=1
        ;;
    --dist-clean)
        DIST_CLEAN=1
        ;;
    -p|--patch)
        PATCHES_ONLY=1
        ;;
    --clang-format)
        CLANG_FORMAT_ONLY=1
        ;;
    --disable-threads)
        ENABLE_THREADS=""
        ;;
    -c|--cached-sources)
        CACHED_SOURCES=1
        ;;
    --incremental)
        # Fast rebuild loop: reuse the existing sources, build trees and install
        # prefix, re-apply patches so edits take effect, and let Ninja do the
        # minimal recompile. Implies --cached-sources and --keep-artifacts.
        INCREMENTAL=1
        CACHED_SOURCES=1
        KEEP_ARTIFACTS=1
        ;;
    -d|--download-sources)
        JUST_SOURCES=1
        ;;
    --llvm-url)
        if [ "$2" ]; then
          LLVM_URL="$2"
          shift
        else
          arg_error "'--llvm-url' requires a non-empty option argument"
        fi
        ;;
    --llvm-url=?*)
        LLVM_URL=${1#*=}
        ;;
    --llvm-url=)
        arg_error "'--llvm-url' requires a non-empty option argument"
        ;;
    --llvm-branch)
        if [ "$2" ]; then
          LLVM_BRANCH="$2"
          shift
        else
          arg_error "'--llvm-branch' requires a non-empty option argument"
        fi
        ;;
    --llvm-branch=?*)
        LLVM_BRANCH=${1#*=}
        ;;
    --llvm-branch=)
        arg_error "'--llvm-branch' requires a non-empty option argument"
        ;;
    --crtlib)
        if [ "$2" ]; then
          LINKED_RUNTIME="$2"
          shift
        else
          arg_error "'--crtlib' requires a non-empty option argument"
        fi
        ;;
    --crtlib=?*)
        LINKED_RUNTIME=${1#*=}
        ;;
    --crtlib=)
        arg_error "'--crtlib' requires a non-empty option argument"
        ;;
    --mingw-url)
        if [ "$2" ]; then
          MINGW_W64_URL="$2"
          shift
        else
          arg_error "'--mingw-url' requires a non-empty option argument"
        fi
        ;;
    --mingw-url=?*)
        MINGW_W64_URL=${1#*=}
        ;;
    --mingw-url=)
        arg_error "'--mingw-url' requires a non-empty option argument"
        ;;
    --mingw-branch)
        if [ "$2" ]; then
          MINGW_W64_BRANCH="$2"
          shift
        else
          arg_error "'--mingw-branch' requires a non-empty option argument"
        fi
        ;;
    --mingw-branch=?*)
        MINGW_W64_BRANCH=${1#*=}
        ;;
    --mingw-branch=)
        arg_error "'--mingw-branch' requires a non-empty option argument"
        ;;
    --win32-winnt)
        if [ "$2" ]; then
          WIN32_WINNT="$2"
          GOT_WIN32_WINNT=1
          shift
        else
          arg_error "'--win32-winnt' requires a non-empty option argument"
        fi
        ;;
    --win32-winnt=?*)
        WIN32_WINNT=${1#*=}
        GOT_WIN32_WINNT=1
        ;;
    --win32-winnt=)
        arg_error "'--win32-winnt' requires a non-empty option argument"
        ;;
    i586)
        BUILD_I586=1
        ;;
    i686|x32)
        BUILD_I686=1
        ;;
    x86_64|x64)
        BUILD_X86_64=1
        ;;
    -a|--all)
        # build every arch; each picks its own _WIN32_WINNT default at
        # dispatch unless the user passed --win32-winnt
        BUILD_I586=1
        BUILD_I686=1
        BUILD_X86_64=1
        ;;
    --package)
        PACKAGE=1
        ;;
    --mmx)
        WANT_MMX=1
        ;;
    --sse2)
        WANT_SSE2=1
        ;;
    --sse3)
        WANT_SSE3=1
        ;;
    --sse41)
        WANT_SSE41=1
        ;;
    --sse42)
        WANT_SSE42=1
        ;;
    --avx)
        WANT_AVX=1
        ;;
    --avx2)
        WANT_AVX2=1
        ;;
    --avx512)
        WANT_AVX512=1
        ;;
    --)
        shift
        break
        ;;
    -?*)
        arg_error "Unknown option '$1'"
        ;;
    ?*)
        arg_error "Unknown architecture '$1'"
        ;;
    *)
        break
  esac

  shift
done

if [ "$ROOT_PATH_ARG" ]; then
  if { [ "$CLEAN" ] || [ "$DIST_CLEAN" ]; } && [ ! -d "$ROOT_PATH_ARG" ]; then
    # don't create the directory just to clean it
    ROOT_PATH="$ROOT_PATH_ARG"
  else
    ROOT_PATH=$(mkdir -p "$ROOT_PATH_ARG" && cd "$ROOT_PATH_ARG" && pwd)
  fi
  # ROOT_PATH moved, so re-derive everything anchored to it
  SRC_PATH="$ROOT_PATH/src"
  BLD_PATH="$ROOT_PATH/bld"
  LOG_FILE="$ROOT_PATH/build.log"
fi

# --clean / --dist-clean are standalone commands: wipe the build dir and exit, no
# arch needed. --dist-clean preserves the src/ tree for a fast cached rebuild (-c).
if [ "$CLEAN" ] || [ "$DIST_CLEAN" ]; then
  clean_build "$DIST_CLEAN"
  exit 0
fi

# --patch is a standalone command: (re)apply patches to already-downloaded
# sources, then exit, without building. Needs no arch. Intended to follow
# --download-sources plus local edits.
if [ "$PATCHES_ONLY" ]; then
  if [ ! -d "$SRC_PATH/llvm-project" ] || [ ! -d "$SRC_PATH/mingw-w64" ]; then
    arg_error "No sources to patch; run --download-sources first"
  fi
  mkdir -p "$ROOT_PATH"
  touch "$LOG_FILE"
  if [ -f "$SRC_PATH/patches/applied_patches" ]; then
    printf "${YEL}Patches already applied.${c0}\n"
  else
    apply_patches || error_exit "Failed to apply patches"
  fi
  exit 0
fi

NUM_BUILDS=$((BUILD_I586 + BUILD_I686 + BUILD_X86_64))
# --download-sources only clones the repos and exits, so it needs no arch
if [ "$NUM_BUILDS" -eq 0 ] && [ ! "$JUST_SOURCES" ]; then
  arg_error "No ARCH was specified"
fi

MISSING_EXECS=""
for exec in g++ cmake ninja git make python3 bzip2 curl diff; do
  if ! command -v "$exec" >/dev/null; then
    MISSING_EXECS="$MISSING_EXECS $exec"
  fi
done
if [ "$MISSING_EXECS" ]; then
  error_exit "Missing required executable(s): $MISSING_EXECS"
fi

if [ "$PACKAGE" ]; then
  if [ "$PREFIX" ]; then
    arg_error "--package cannot be combined with --prefix (it packages the per-arch build dirs)"
  fi
  if ! command -v zip >/dev/null; then
    error_exit "--package requires 'zip' to be installed"
  fi
fi

TOTAL_STEPS=0

# source download: 2 clones + config.guess copy
if [ ! "$CACHED_SOURCES" ]; then
  TOTAL_STEPS=$((TOTAL_STEPS + 3))
fi

# winpthreads (3 steps) is built only in Phase 1.
if [ "$ENABLE_THREADS" ]; then
  THREADS_STEPS=3
else
  THREADS_STEPS=0
fi

THREADS_STEPS=$((THREADS_STEPS * NUM_BUILDS))
# Per arch, two phases:
#   Phase 1 (Linux-hosted): LLVM(3) + headers(2) + crt(3) + compiler-rt(3) +
#                           runtimes(3) = 14 (winpthreads counted separately).
#   Phase 2 (Windows-hosted): LLVM cross(3) + 2 copies + gendef(3) + clang-format(1)
#                             + 4 host tools = 13.
BUILD_STEPS=$(( (14 + 13) * NUM_BUILDS ))

# one packaging step (the zip) per built arch
if [ "$PACKAGE" ]; then
  PACKAGE_STEPS=$NUM_BUILDS
else
  PACKAGE_STEPS=0
fi

if [ "$JUST_SOURCES" ]; then
  TOTAL_STEPS=3
elif [ "$CLANG_FORMAT_ONLY" ]; then
  # per arch: Phase 2 configure(1) + build clang-format(1) + install(1); assumes
  # Phase 1 is reused (if it has to rebuild, the counter just overshoots).
  TOTAL_STEPS=$((TOTAL_STEPS + 3 * NUM_BUILDS))
else
  TOTAL_STEPS=$((TOTAL_STEPS + THREADS_STEPS + BUILD_STEPS + PACKAGE_STEPS))
fi

if [ "$PREFIX" ]; then
  I586_PREFIX="$PREFIX"
  I686_PREFIX="$PREFIX"
  X86_64_PREFIX="$PREFIX"
else
  I586_PREFIX="$ROOT_PATH/i586_llvm"
  I686_PREFIX="$ROOT_PATH/i686_llvm"
  X86_64_PREFIX="$ROOT_PATH/x64_llvm"
fi

CURRENT_STEP=1

# clean log file for execute()
mkdir -p "$ROOT_PATH"
rm -f "$LOG_FILE"
touch "$LOG_FILE"


if [ ! "$CACHED_SOURCES" ] || [ "$JUST_SOURCES" ]; then
  download_sources
  if [ "$JUST_SOURCES" ]; then
    exit 0;
  fi
else
  if [ ! -f "$SRC_PATH/config.guess" ]; then
    arg_error "No sources found, run with --download sources first."
  fi
  if [ "$CACHED_SOURCES" ]; then
    log "${YEL}NOTE: Using cached sources.${c0}\n"
  fi
fi

# --incremental: reset the kept sources to pristine and re-apply patches (mtime-
# preserving) so patch edits take effect and Ninja recompiles only what changed.
# Runs once here; build()'s own apply_patches is then a no-op (sentinel present).
if [ "$INCREMENTAL" ]; then
  reapply_patches_incremental
fi

BUILD=$(sh "$SRC_PATH/config.guess")

ADD_TO_PATH=()

if [ "$BUILD_I586" ]; then
  [ "$GOT_WIN32_WINNT" ] || WIN32_WINNT="0x0400"
  if [ "$WANT_MMX" ]; then
    USE_MMX=true
  fi
  build i586 "$I586_PREFIX"
  ADD_TO_PATH+=("'$I586_PREFIX/bin'")
fi

if [ "$BUILD_I686" ]; then
  [ "$GOT_WIN32_WINNT" ] || WIN32_WINNT="0x0500"
  if [ "$WANT_SSE2" ]; then
    USE_SSE2=true
  fi
  if [ "$WANT_SSE3" ]; then
    USE_SSE3=true
  fi
  if [ "$WANT_SSE41" ]; then
    USE_SSE41=true
  fi
  if [ "$WANT_SSE42" ]; then
    USE_SSE42=true
  fi
  build i686 "$I686_PREFIX"
  ADD_TO_PATH+=("'$I686_PREFIX/bin'")
fi

if [ "$BUILD_X86_64" ]; then
  [ "$GOT_WIN32_WINNT" ] || WIN32_WINNT="0x0502"
  if [ "$WANT_SSE3" ]; then
    USE_SSE3=true
  fi
  if [ "$WANT_SSE41" ]; then
    USE_SSE41=true
  fi
  if [ "$WANT_SSE42" ]; then
    USE_SSE42=true
  fi
  if [ "$WANT_AVX" ]; then
    USE_AVX=true
  fi
  if [ "$WANT_AVX2" ]; then
    USE_AVX2=true
  fi
  if [ "$WANT_AVX512" ]; then
    USE_AVX512=true
  fi
  build x86_64 "$X86_64_PREFIX"
  ADD_TO_PATH+=("'$X86_64_PREFIX/bin'")
fi

# Reaching here means every requested build succeeded (build() aborts on error).
# Package each built arch; the 64-bit one is named x64.zip.
if [ "$PACKAGE" ]; then
  [ "$BUILD_I586" ]   && package_arch i586_llvm i586_llvm
  [ "$BUILD_I686" ]   && package_arch i686_llvm i686_llvm
  [ "$BUILD_X86_64" ] && package_arch x64_llvm x64_llvm
fi

if [ ! "$KEEP_ARTIFACTS" ]; then
  if [ ! "$CACHED_SOURCES" ]; then
    remove_path "$SRC_PATH"
  fi
  remove_path "$BLD_PATH"
  # the Phase 1 Linux-hosted toolchains are only an intermediate used to drive
  # the Canadian cross; drop them unless the user asked to keep artifacts
  remove_path "$ROOT_PATH/linux-cross"
  # keep build.log: it's the record of the build, and --clean preserves it as build.log.old
fi

printf "${GRE}Done! \n${c0}Built Windows-hosted LLVM MinGW-w64 toolchain(s) at: \n"
for add_to_path in "${ADD_TO_PATH[@]}"; do
  printf "${bold}%s ${c0}\n" "$add_to_path"
done
printf "${c0}Copy the prefix to a Windows machine and add its ${bold}bin\\\\${c0} to PATH.\n"

exit 0
