# MinGW Cross Compiler Build Script  <img src="./assets/mingw-w64.svg" width="38">

mingw-w64-build is a Bash script to build a [MinGW-w64](https://mingw-w64.org)
cross compiler for i586/i686 (Win32) and x86_64 (Win64).  

This is a fork of [Zeranoe's mingw-w64-build repo](https://github.com/Zeranoe/mingw-w64-build#readme), and is specifically designed to support very old
versions of Windows, and provide much more customizability including many [SIMD](https://en.wikipedia.org/wiki/Single_instruction,_multiple_data) optimization options.  
I use it with [GN-Legacy](https://github.com/Alex313031/gn-legacy#readme) on Linux to compile many of my Win32 projects, that I specifically code to be compatible with legacy Windows for fun.

## Default Branches
* [MinGW-w64](https://mingw-w64.org) 16
* [Binutils](https://www.gnu.org/software/binutils/) binutils-2_46-branch
* [GCC](https://gcc.gnu.org/) releases/gcc-16

## Target Platforms

The i586 build targets Pentium-MMX and Windows NT 4.0. It lacks SSE instructions.  
The i686 build targets Pentium III and Windows 2000 by default. It has SSE instructions.  
The x86_64 (x64) build targets Windows Server 2003 by default. It has SSE2 instructions.  

 - There are flags to control the minimum Windows target, and to adjust SIMD options, all the way from SSE to SSE4 to AVX and AVX2

## Usage
 - See `mingw-w64-build --help` for all build options.

Some common options are:

`--debug` - Make a debug build instead of a release build, for debugging issues in the CRT itself.  
`--verbose` - Verbose logging output  
`--jobs` - Adjust number of concurrent build jobs  

### Host Platforms
mingw-w64-build should run on Ubuntu, Debian, Cygwin, macOS (with Homebrew), and other __bash__ based shells.
The host tools compile with SSE3 by default: Any reasonably modern OS/Machine should handle it.

### Default Prefix
`$PWD/build/bld/i686` and `$PWD/build/bld/x86_64` are the
default install locations, but this location can be modified with the `--prefix` option.
To ensure the new compilers are available system-wide, add the dir` to the `$PATH`.  
It does not need to be "installed", the prefix simply chooses where to put built files: the toolchain is fully portable.

## License
mingw-w64-build is licensed under the GNU GPL 3.0 or later. A copy of the
license can be found in the [LICENSE.md](./LICENSE.md) file.
