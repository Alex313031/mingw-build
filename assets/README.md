# Assets

This directory contains assets like `config.guess`, images, and the sources
for extra programs bundled into the MinGW build's `bin` dir.

[`config.guess`](./config.guess) - Used by the build scripts to detect the host configuration.

In [./src/](./src) we have utilities adapted from [w64devkit](https://github.com/skeeto/w64devkit/tree/master/src):

1. [peports.c](./src/peports.c) - PE export/import table listing cmdline program.  
2. [pkg-config.c](./src/pkg-config.c) - Single file minimal pkg-config replacement.  
3. [rexxd.c](./src/rexxd.c) - Replacement for xxd from w64devkit. This can do hex dumps.  
4. [uuidgen.c](./src/uuidgen.c) - Fast uuidgen replacement, can be used in widl.  

And [clang-target-wrapper.c](./src/clang-target-wrapper.c) - LLVM toolchain entry-point wrapper; compiled once and stamped out as every `<triple>-<tool>.exe`.

-----

We also have the lovely classic Windows logos/banners:

<table>
  <tr>
    <td align="center" valign="middle"><img src="./WinNT4Workstation_Logo.svg" height="80"></td>
    <td align="center" valign="middle"><img src="./Win2000_Logo.svg" height="80"></td>
    <td align="center" valign="middle"><img src="./WinXP_Logo.svg" height="80"></td>
    <td align="center" valign="middle"><img src="./WinVista_Orb.svg" height="88"></td>
  </tr>
  <tr>
    <td align="center"><b>Windows NT 4.0</b></td>
    <td align="center"><b>Windows 2000</b></td>
    <td align="center"><b>Windows XP</b></td>
    <td align="center"><b>Windows Vista</b></td>
  </tr>
</table>

<!-- Windows 7 orb — uncomment the two cells to add it as a fifth column:
    <td align="center" valign="middle"><img src="./Win7_Orb.svg" height="88"></td>
    <td align="center"><b>Windows 7</b></td>
-->
