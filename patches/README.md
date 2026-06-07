# Patches

This directory contains patches for MinGW, GCC, Binutils, and LLVM to support legacy versions of Windows.

Modern MinGW/LLVM/GCC/MSVC only support Windows Vista+ (2006), and SSE2+ (CPU's made after 2003).
With these patches and compiler flag tuning, we are able to produce toolchains that support
Windows NT 4.0 (1996), 2000 (2000), XP(2001), and CPUs down to the original Pentium (1994).

The LLVM patches were taken and modified from [this repo](https://github.com/mon/llvm-mingw-xp).  
Some of the MinGW/GCC patches were taken and modified from [w64devkit](https://github.com/skeeto/w64devkit/tree/master).  
A notable exception is the rand_s-win2k.patch, which I made myself for MinGW's rand_s used in std::random as well.

## List of patches and their purpose

### MinGW

[gendef-no-comment.patch](./mingw/gendef-no-comment.patch) - Makes `gendef` not put annoying copyright lines in the top of your *.def* files.

[rand_s-win2k.patch](./mingw/rand_s-win2k.patch) - Fixes MinGW CRT `rand_s` incompatibility with Windows NT 4.0/2000, by using [`CryptGenRandom`](https://en.wikipedia.org/wiki/CryptGenRandom) instead of
                                                   XP+ [`RtlGenRandom`](https://learn.microsoft.com/en-us/windows/win32/api/ntsecapi/nf-ntsecapi-rtlgenrandom) for cryptographically secure random number generation.

[sdkddkver.h.h](./mingw/sdkddkver.h) and [winsdkver.h](./mingw/winsdkver.h) - Custom written replacements for these MSVC's headers, with expanded macros and definitions for old Windows.

### GCC

[gcc-stdcall-align.patch](./gcc/gcc-stdcall-align.patch) - Aligns x86 [__stdcall](https://learn.microsoft.com/en-us/cpp/cpp/stdcall) 4 byte stacks with GCC's 16 byte stack alignment expectations, increasing performance slightly.

[gcc-trap-terminate.patch](./gcc/gcc-trap-terminate.patch) - Replaces `std::terminate`'s __std::abort__ function with a __&#95;&#95;builtin_trap__ trap instruction.

[gcc-tzdb-getdynamic.patch](./gcc/gcc-tzdb-getdynamic.patch) - Fixes C++20 compatability by using [GetTimeZoneInformation](https://learn.microsoft.com/en-us/windows/win32/api/timezoneapi/nf-timezoneapi-gettimezoneinformation) instead of
                                                               Vista+ [GetDynamicTimeZoneInformation](https://learn.microsoft.com/en-us/windows/win32/api/timezoneapi/nf-timezoneapi-getdynamictimezoneinformation).

### Binutils

[binutils-dlltool-zero-ordinals.patch](./binutils-gdb/binutils-dlltool-zero-ordinals.patch) - Prevents randomizing function ordinals in libraries, which is good for reproducible builds and making static libraries more compatible.

[gdb-alternate-main.patch](./binutils-gdb/gdb-alternate-main.patch) - Allows [GDB](https://sourceware.org/gdb/) to pick up Win32 specific entry point function names like __wWinMain__, __mainCRTStartup__, etc.

### LLVM

[compiler-rt-emutls-pre-vista.patch](./llvm/compiler-rt-emutls-pre-vista.patch) - Replaces Vista+ [InitOnceExecuteOnce](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-initonceexecuteonce)
                                                                                with [InterlockedCompareExchange](https://learn.microsoft.com/en-us/windows/win32/api/winnt/nf-winnt-interlockedcompareexchange)
                                                                                for [TLS](https://learn.microsoft.com/en-us/windows/win32/procthread/thread-local-storage).

[libcxx-legacy-filesystem.patch](./llvm/libcxx-legacy-filesystem.patch) - 

[libcxx-legacy-msvcrt-locale.patch](./llvm/libcxx-legacy-msvcrt-locale.patch) - 

[libcxx-legacy-msvcrt-wcrtomb_s.patch](./llvm/libcxx-legacy-msvcrt-wcrtomb_s.patch) - 

[libunwind-rwmutex-pre-vista.patch](./llvm/libunwind-rwmutex-pre-vista.patch) - 
