#ifndef CSTD_BOOL_H_
#define CSTD_BOOL_H_

/* Copyright (c) 2026 Alex313031. */

/* Portable, C/C++ standard-agnostic bool header.
 * I was frustrated by the lack of universal support of this basic data type.
 * Include this anytime <stdbool.h> or <cstdbool> is missing or lacking; it
 * yields a working bool/true/false on everything from C89 through C23 and C++.
 * Comments are /-style so the header itself is valid strict ISO C90. */

#ifndef __bool_true_false_are_defined

#ifdef __cplusplus
 /* C++ has bool/true/false as language keywords -- nothing to define. As a
  * convenience for C sources compiled as C++, also expose _Bool (GCC and Clang
  * accept it as an extension anyway). NOTE: do NOT define BOOL here -- that is a
  * distinct 4-byte Win32 type (typedef int BOOL) and aliasing it to bool breaks
  * windows.h. */
 #ifndef _Bool
  #define _Bool bool
 #endif
#elif defined __STDC_VERSION__ && __STDC_VERSION__ > 201710L
 /* C23 or later: bool, true and false are builtin keywords. */
#elif defined __STDC_VERSION__ && __STDC_VERSION__ >= 199901L
 /* C99/C11/C17: _Bool is a keyword; map bool/true/false onto it, as
  * <stdbool.h> itself does. */
 #define bool  _Bool
 #define true  1
 #define false 0
#else
 /* Pre-C99 (C89/C90): there is no _Bool keyword, so fall back to a 1-byte
  * unsigned char (matching _Bool's size). Unlike _Bool it does not normalize
  * non-zero values to 1, which is the best a pre-C99 emulation can do. */
 typedef unsigned char _CStdBool_bool;
 #define bool  _CStdBool_bool
 #define true  1
 #define false 0
#endif /* __cplusplus */

/* Signal that bool/true/false are present (mirrors <stdbool.h> so a later
 * include of the real header is a no-op instead of a redefinition). */
#define __bool_true_false_are_defined 1

#endif /* !__bool_true_false_are_defined */

#endif /* CSTD_BOOL_H_ */
