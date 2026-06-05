// Master include file for versioning windows SDK/DDK.

// Sourced from WinSDK 10.1.26100.7175

// Cleaned up & expanded by Alex313031 (c) 2026

// Must keep header guard name
#ifndef _INC_SDKDDKVER
#define _INC_SDKDDKVER

#ifdef _MSC_VER
 #pragma once
#endif  // _MSC_VER

// _WIN32_WINNT version constants
#define _WIN32_WINNT_NT4   0x0400
#define _WIN32_WINNT_WIN2K 0x0500
#define _WIN32_WINNT_WINXP 0x0501
#define _WIN32_WINNT_WS03  0x0502
#define _WIN32_WINNT_VISTA 0x0600
#define _WIN32_WINNT_WIN7  0x0601
#define _WIN32_WINNT_WIN8  0x0602
#define _WIN32_WINNT_WIN81 0x0603
#define _WIN32_WINNT_WIN10 0x0A00
#define _WIN32_WINNT_WIN11 0x0A00
// Extra aliases
#define _WIN32_WINNT_WIN4         _WIN32_WINNT_NT4
#define _WIN32_WINNT_WIN5         _WIN32_WINNT_WIN2K
#define _WIN32_WINNT_WHISTLER     _WIN32_WINNT_WINXP
#define _WIN32_WINNT_WIN51        _WIN32_WINNT_WINXP
#define _WIN32_WINNT_WINXP64      _WIN32_WINNT_WS03
#define _WIN32_WINNT_WIN52        _WIN32_WINNT_WS03
#define _WIN32_WINNT_WIN6         _WIN32_WINNT_VISTA
#define _WIN32_WINNT_WS08         _WIN32_WINNT_VISTA
#define _WIN32_WINNT_LONGHORN     _WIN32_WINNT_VISTA
#define _WIN32_WINNT_WIN61        _WIN32_WINNT_WIN7
#define _WIN32_WINNT_WS08R2       _WIN32_WINNT_WIN7
#define _WIN32_WINNT_WIN62        _WIN32_WINNT_WIN8
#define _WIN32_WINNT_WS2012       _WIN32_WINNT_WIN8
#define _WIN32_WINNT_WIN63        _WIN32_WINNT_WIN81
#define _WIN32_WINNT_WS2012R2     _WIN32_WINNT_WIN81
#define _WIN32_WINNT_WINBLUE      _WIN32_WINNT_WIN81
#define _WIN32_WINNT_WINTHRESHOLD _WIN32_WINNT_WIN10

// _WIN32_IE_ version constants
#define _WIN32_IE_IE1     0x0100 // IE 1.0
#define _WIN32_IE_IE20    0x0200
#define _WIN32_IE_IE30    0x0300
#define _WIN32_IE_IE302   0x0302
#define _WIN32_IE_IE40    0x0400
#define _WIN32_IE_IE401   0x0401
#define _WIN32_IE_IE50    0x0500
#define _WIN32_IE_IE501   0x0501
#define _WIN32_IE_IE55    0x0550
#define _WIN32_IE_IE60    0x0600
#define _WIN32_IE_IE60SP1 0x0601
#define _WIN32_IE_IE60S03 0x0602 // Custom: Server 2003 RTM IE6; stock SDK skips 0x0602
#define _WIN32_IE_IE60SP2 0x0603
#define _WIN32_IE_IE70    0x0700
#define _WIN32_IE_IE80    0x0800
#define _WIN32_IE_IE90    0x0900
#define _WIN32_IE_IE100   0x0A00
#define _WIN32_IE_IE110   0x0A00 // 11.0 doesn't have a separate version

// IE <-> OS version mapping
// Win 95 supports IE versions 1.00 -> 5.5 SP1
#define _WIN32_IE_WIN95        _WIN32_IE_IE1
// NT4 supports IE versions 2.0 -> 6.0 SP1
#define _WIN32_IE_NT4          _WIN32_IE_IE20
#define _WIN32_IE_WIN4         _WIN32_IE_IE20
#define _WIN32_IE_NT4SP1       _WIN32_IE_IE20
#define _WIN32_IE_NT4SP2       _WIN32_IE_IE20
#define _WIN32_IE_NT4SP3       _WIN32_IE_IE302
#define _WIN32_IE_NT4SP4       _WIN32_IE_IE401
#define _WIN32_IE_NT4SP5       _WIN32_IE_IE401
#define _WIN32_IE_NT4SP6       _WIN32_IE_IE50
// Win 98 supports IE versions 4.01 -> 6.0 SP1
#define _WIN32_IE_WIN98        _WIN32_IE_IE401
// Win 98SE supports IE versions 5.0 -> 6.0 SP1
#define _WIN32_IE_WIN98SE      _WIN32_IE_IE50
// Win ME supports IE versions 5.5 -> 6.0 SP1
#define _WIN32_IE_WINME        _WIN32_IE_IE55
// Win 2000 supports IE versions 5.01 -> 6.0 SP1
#define _WIN32_IE_WIN2K        _WIN32_IE_IE501
#define _WIN32_IE_WIN5         _WIN32_IE_IE501
#define _WIN32_IE_WIN2KSP1     _WIN32_IE_IE501
#define _WIN32_IE_WIN2KSP2     _WIN32_IE_IE501
#define _WIN32_IE_WIN2KSP3     _WIN32_IE_IE501
#define _WIN32_IE_WIN2KSP4     _WIN32_IE_IE501
// Win XP / Server 2003 supports IE versions 6.0 -> 8.0
#define _WIN32_IE_WHISTLER     _WIN32_IE_IE60
#define _WIN32_IE_WIN51        _WIN32_IE_IE60
#define _WIN32_IE_XP           _WIN32_IE_IE60
#define _WIN32_IE_XPSP1        _WIN32_IE_IE60SP1
#define _WIN32_IE_XPSP2        _WIN32_IE_IE60SP2
#define _WIN32_IE_XP64         _WIN32_IE_IE60S03
#define _WIN32_IE_WS03         _WIN32_IE_IE60S03
#define _WIN32_IE_WIN52        _WIN32_IE_IE60S03
#define _WIN32_IE_WS03SP1      _WIN32_IE_IE60SP2
// Win Vista / Server 2008 supports IE versions 7.0 -> 9.0
#define _WIN32_IE_WIN6         _WIN32_IE_IE70
#define _WIN32_IE_WS08         _WIN32_IE_IE70
#define _WIN32_IE_LONGHORN     _WIN32_IE_IE70
#define _WIN32_IE_VISTA        _WIN32_IE_IE70
// Win 7 / Server 2008 R2 supports IE versions 8.0 -> 11.0
#define _WIN32_IE_WIN7         _WIN32_IE_IE80
#define _WIN32_IE_WIN61        _WIN32_IE_IE80
#define _WIN32_IE_WS08R2       _WIN32_IE_IE80
// Windows 8 / Server 2012 supports IE versions 10.0 -> 11.0
#define _WIN32_IE_WIN8         _WIN32_IE_IE100
#define _WIN32_IE_WIN62        _WIN32_IE_IE100
#define _WIN32_IE_WS2012       _WIN32_IE_IE100
// Windows 8.1 / Server 2012 R2 supports IE version 11.0
#define _WIN32_IE_WIN81        _WIN32_IE_IE110
#define _WIN32_IE_WIN63        _WIN32_IE_IE110
#define _WIN32_IE_WINBLUE      _WIN32_IE_IE110
#define _WIN32_IE_WS2012R2     _WIN32_IE_IE110
// Windows 10 / 11 and server counterparts only support the last IE version 11.0
#define _WIN32_IE_WINTHRESHOLD _WIN32_IE_IE110
#define _WIN32_IE_WIN10        _WIN32_IE_IE110
#define _WIN32_IE_WIN11        _WIN32_IE_IE110

// NTDDI version constants
#define NTDDI_WIN4         0x04000000
#define NTDDI_NT4          NTDDI_WIN4
// Win 2000
#define NTDDI_WIN2K        0x05000000
#define NTDDI_WIN5         NTDDI_WIN2K
#define NTDDI_WIN2KSP1     0x05000100
#define NTDDI_WIN2KSP2     0x05000200
#define NTDDI_WIN2KSP3     0x05000300
#define NTDDI_WIN2KSP4     0x05000400
// Win XP
#define NTDDI_WINXP        0x05010000
#define NTDDI_WIN51        NTDDI_WINXP
#define NTDDI_WHISTLER     NTDDI_WINXP
#define NTDDI_WINXPSP1     0x05010100
#define NTDDI_WINXPSP2     0x05010200
#define NTDDI_WINXPSP3     0x05010300
// Win Server 2003 / Win XP x64
#define NTDDI_WS03         0x05020000
#define NTDDI_WIN52        NTDDI_WS03
#define NTDDI_WINXP64      NTDDI_WS03
#define NTDDI_WS03SP1      0x05020100
#define NTDDI_WS03SP2      0x05020200
// Windows Vista / Server 2008
#define NTDDI_VISTA        0x06000000
#define NTDDI_WIN6         NTDDI_VISTA
#define NTDDI_VISTASP1     0x06000100
#define NTDDI_VISTASP2     0x06000200
#define NTDDI_LONGHORN     NTDDI_VISTA
#define NTDDI_WS08         NTDDI_VISTASP1
#define NTDDI_WS08SP2      NTDDI_VISTASP2
// Windows 7 / Server 2008 R2
#define NTDDI_WIN7         0x06010000
#define NTDDI_WIN61        NTDDI_WIN7
#define NTDDI_WS08R2       NTDDI_WIN7
// Windows 8 / Server 2012
#define NTDDI_WIN8         0x06020000
#define NTDDI_WIN62        NTDDI_WIN8
#define NTDDI_WS2012       NTDDI_WIN8
// Windows 8.1 / Server 2012 R2
#define NTDDI_WIN81        0x06030000
#define NTDDI_WIN63        NTDDI_WIN81
#define NTDDI_WINBLUE      NTDDI_WIN81
#define NTDDI_WS2012R2     NTDDI_WIN81
// Windows 10 / Server 2016/2019/2022
#define NTDDI_WIN10        0x0A000000 // Version 1507, Build 10240, "Threshold"
#define NTDDI_WINTHRESHOLD NTDDI_WIN10 // Original Release
#define NTDDI_WIN10_TH2    0x0A000001 // Version 1511, Build 10586, "Threshold 2"
#define NTDDI_WIN10_RS1    0x0A000002 // Version 1607, Build 14393, "Redstone" - Server 2016
#define NTDDI_WIN10_RS2    0x0A000003 // Version 1703, Build 15063, "Redstone 2"
#define NTDDI_WIN10_RS3    0x0A000004 // Version 1709, Build 16299, "Redstone 3"
#define NTDDI_WIN10_RS4    0x0A000005 // Version 1803, Build 17134, "Redstone 4"
#define NTDDI_WIN10_RS5    0x0A000006 // Version 1809, Build 17763, "Redstone 5" - Server 2019
#define NTDDI_WIN10_1809   0x0A000006 // 1809
#define NTDDI_WIN10_19H1   0x0A000007 // Version 1903, Build 18362, 19H1
#define NTDDI_WIN10_19H2   NTDDI_WIN10_19H1 // Version 1909, Build 18363, 19H2
#define NTDDI_WIN10_VN     NTDDI_WIN10_19H2 // "Vanadium"
#define NTDDI_WIN10_20H1   0x0A000008 // Version 2004, Build 19041, 20H1
#define NTDDI_WIN10_VB     NTDDI_WIN10_20H1 // "Vibranium"
#define NTDDI_WIN10_20H2   0x0A000009 // Version 20H2, Build 19042
#define NTDDI_WIN10_MN     NTDDI_WIN10_20H2 // "Manganese"
#define NTDDI_WIN10_21H1   0x0A00000A // Version 21H1, Build 19043 (Server 2022 "Iron" is Build 20348)
#define NTDDI_WIN10_FE     NTDDI_WIN10_21H1 // "Iron"
#define NTDDI_WIN10_21H2   0x0A00000B // Version 21H2, Build 19044 - Enterprise LTSC
#define NTDDI_WIN10_CO     NTDDI_WIN10_21H2 // "Cobalt"
#define NTDDI_WIN10_22H2   0x0A00000C // Version 22H2, Build 19045
#define NTDDI_WIN10_NI     NTDDI_WIN10_22H2 // "Nickel"
// Windows 11 / Server 2025
#define NTDDI_WIN11_21H2   0x0A00000B // Version 21H2, Build 22000
#define NTDDI_WIN11_CO     NTDDI_WIN11_21H2 // "Cobalt"
#define NTDDI_WIN11_22H2   0x0A00000C // Version 22H2, Build 22621
#define NTDDI_WIN11_NI     NTDDI_WIN11_22H2 // "Nickel"
#define NTDDI_WIN11_CU     0x0A00000D // 23H1, "Copper"
#define NTDDI_WIN11_23H2   0x0A00000E // 23H2, Build 22631
#define NTDDI_WIN11_ZN     NTDDI_WIN11_23H2 // "Zinc"
#define NTDDI_WIN11_GA     0x0A00000F // 24H1, "Gallium"
#define NTDDI_WIN11_24H2   0x0A000010 // 24H2, Build 26100 - Server 2025
#define NTDDI_WIN11_GE     NTDDI_WIN11_24H2 // "Germanium"

// Default WDK version, Windows 10 1809 / Server 2019
#define WDK_NTDDI_VERSION  NTDDI_WIN10_RS5

// BitMasks for version macros
#define OSVERSION_MASK     0xFFFF0000
#define SPVERSION_MASK     0x0000FF00
#define SUBVERSION_MASK    0x000000FF

// Macros to extract various version fields from the NTDDI version
#define OSVER(Version)  ((Version)  & OSVERSION_MASK)
#define SPVER(Version)  (((Version) & SPVERSION_MASK) >> 8)
#define SUBVER(Version) (((Version) & SUBVERSION_MASK) )
#define NTDDI_VERSION_FROM_WIN32_WINNT2(ver) ver##0000
#define NTDDI_VERSION_FROM_WIN32_WINNT(ver)  NTDDI_VERSION_FROM_WIN32_WINNT2(ver)

// Default to Windows XP if no target is specified (_CHICAGO_ = Win9x family)
#if !defined(_WIN32_WINNT) && !defined(_CHICAGO_)
 #define _WIN32_WINNT _WIN32_WINNT_WINXP
#endif

// Set WINVER based on _WIN32_WINNT
#ifndef WINVER
 #ifdef _WIN32_WINNT
  #define WINVER _WIN32_WINNT
 #else
  #define WINVER _WIN32_WINNT_WINXP
 #endif
#endif

// Set NTDDI_VERSION based on _WIN32_WINNT
#ifndef NTDDI_VERSION
 #ifdef _WIN32_WINNT
  #if (_WIN32_WINNT < _WIN32_WINNT_WIN10)
   #define NTDDI_VERSION NTDDI_VERSION_FROM_WIN32_WINNT(_WIN32_WINNT)
  #else // _WIN32_WINNT can't distinguish Win10/11 builds, use the WDK default
   #define NTDDI_VERSION WDK_NTDDI_VERSION
  #endif
 #else
  #define NTDDI_VERSION NTDDI_WINXP
 #endif
#endif

// Set _WIN32_IE based on _WIN32_WINNT, mainly for comctl32
#ifndef _WIN32_IE
 #define _WIN32_IE_DEFAULT _WIN32_IE_IE60 // Fallback to commctrl 6.0
 #ifdef _WIN32_WINNT
  #if (_WIN32_WINNT <= _WIN32_WINNT_NT4)
   #define _WIN32_IE  _WIN32_IE_IE50
  #elif (_WIN32_WINNT <= _WIN32_WINNT_WIN2K)
   #define _WIN32_IE  _WIN32_IE_IE501
  #elif (_WIN32_WINNT <= _WIN32_WINNT_WINXP)
   #define _WIN32_IE  _WIN32_IE_IE60
  #elif (_WIN32_WINNT <= _WIN32_WINNT_WS03)
   #define _WIN32_IE  _WIN32_IE_WS03
  #elif (_WIN32_WINNT <= _WIN32_WINNT_VISTA)
   #define _WIN32_IE  _WIN32_IE_LONGHORN
  #elif (_WIN32_WINNT <= _WIN32_WINNT_WIN7)
   #define _WIN32_IE  _WIN32_IE_WIN7
  #elif (_WIN32_WINNT <= _WIN32_WINNT_WIN8)
   #define _WIN32_IE  _WIN32_IE_WIN8
  #elif (_WIN32_WINNT <= _WIN32_WINNT_WIN81)
   #define _WIN32_IE  _WIN32_IE_WIN81
  #elif (_WIN32_WINNT >= _WIN32_WINNT_WIN10)
   #define _WIN32_IE  _WIN32_IE_WIN10
  #else
   #define _WIN32_IE  _WIN32_IE_DEFAULT
  #endif
 #else // !_WIN32_WINNT
   #define _WIN32_IE  _WIN32_IE_DEFAULT
 #endif
#endif // !_WIN32_IE

// Sanity check for compatible versions
#if defined(_WIN32_WINNT) && !defined(MIDL_PASS) && !defined(RC_INVOKED)
 // NT4 special case
 #if (defined(WINVER) && (WINVER < 0x0400) && (_WIN32_WINNT > 0x0400))
  #error WINVER setting conflicts with _WIN32_WINNT setting
 #endif // 0x0400
 // Check NTDDI _WIN32_WINNT sanity
 #if (((OSVERSION_MASK & NTDDI_VERSION) == NTDDI_WIN2K) && (_WIN32_WINNT != _WIN32_WINNT_WIN2K))
  #error NTDDI_VERSION setting conflicts with _WIN32_WINNT setting
 #endif // 0x0500
 #if (((OSVERSION_MASK & NTDDI_VERSION) == NTDDI_WINXP) && (_WIN32_WINNT != _WIN32_WINNT_WINXP))
  #error NTDDI_VERSION setting conflicts with _WIN32_WINNT setting
 #endif // 0x0501
 #if (((OSVERSION_MASK & NTDDI_VERSION) == NTDDI_WS03) && (_WIN32_WINNT != _WIN32_WINNT_WS03))
  #error NTDDI_VERSION setting conflicts with _WIN32_WINNT setting
 #endif // 0x0502
 #if (((OSVERSION_MASK & NTDDI_VERSION) == NTDDI_VISTA) && (_WIN32_WINNT != _WIN32_WINNT_VISTA))
  #error NTDDI_VERSION setting conflicts with _WIN32_WINNT setting
 #endif // 0x0600
 #if (((OSVERSION_MASK & NTDDI_VERSION) == NTDDI_WIN7) && (_WIN32_WINNT != _WIN32_WINNT_WIN7))
  #error NTDDI_VERSION setting conflicts with _WIN32_WINNT setting
 #endif // 0x0601
 #if (((OSVERSION_MASK & NTDDI_VERSION) == NTDDI_WIN8) && (_WIN32_WINNT != _WIN32_WINNT_WIN8))
  #error NTDDI_VERSION setting conflicts with _WIN32_WINNT setting
 #endif // 0x0602
 #if (((OSVERSION_MASK & NTDDI_VERSION) == NTDDI_WINBLUE) && (_WIN32_WINNT != _WIN32_WINNT_WIN81))
  #error NTDDI_VERSION setting conflicts with _WIN32_WINNT setting
 #endif // 0x0603
 #if (((OSVERSION_MASK & NTDDI_VERSION) == NTDDI_WIN10) && (_WIN32_WINNT != _WIN32_WINNT_WIN10))
  #error NTDDI_VERSION setting conflicts with _WIN32_WINNT setting
 #endif // 0x0A00
 // Check for max installable version
 #if ((_WIN32_WINNT < _WIN32_WINNT_WIN2K) && (_WIN32_IE > _WIN32_IE_IE60SP1))
  #error _WIN32_WINNT settings conflicts with _WIN32_IE setting
 #endif
 #if ((_WIN32_WINNT < _WIN32_WINNT_WINXP) && (_WIN32_IE > _WIN32_IE_IE60SP2))
  #error _WIN32_WINNT settings conflicts with _WIN32_IE setting
 #endif
 #if ((_WIN32_WINNT < _WIN32_WINNT_VISTA) && (_WIN32_IE > _WIN32_IE_IE80))
  #error _WIN32_WINNT settings conflicts with _WIN32_IE setting
 #endif
 #if ((_WIN32_WINNT < _WIN32_WINNT_WIN7) && (_WIN32_IE > _WIN32_IE_IE90))
  #error _WIN32_WINNT settings conflicts with _WIN32_IE setting
 #endif
 #if ((_WIN32_WINNT > _WIN32_WINNT_WIN8) && (_WIN32_IE < _WIN32_IE_IE100))
  #error _WIN32_WINNT settings conflicts with _WIN32_IE setting
 #endif
#endif // defined(_WIN32_WINNT) && !defined(MIDL_PASS) && !defined(RC_INVOKED)

#endif // _INC_SDKDDKVER

