#ifndef UFLOAT_H_
#define UFLOAT_H_

// Copyright (c) 2026 Alex313031.
//
// EXPERIMENTAL: "ufloat" -- an unsigned float. A float-like value that can never
// hold anything below 0.0f. Constructing or assigning from a negative SATURATES
// to 0.0f (and, if UFLOAT_MAX is defined, clamps the top end too) -- the low end
// is bounded exactly the way an unsigned integer's is.
//
// This is the C++ (header) realization of the idea. It reads as a plain float
// (implicit conversion) and clamps on every write, so it drops into normal float
// math yet can never STORE a negative:
//
//     ufloat u = 3.0f;
//     u -= 5.0f;        // computes -2.0f as float, clamps to 0.0f on store
//     float f = u;      // f == 0.0f
//
// It needs operator overloading, so it is C++ only. A genuine C-level *builtin*
// ufloat would require compiler front-end changes and a non-standard "run code on
// every store" semantic; see the notes at the bottom of this file.
//
// Options (define before including):
//   UFLOAT_MAX <expr>   upper saturation bound (default: no upper bound / +inf)
//   UFLOAT_CHECKED      assert() on a negative or NaN write instead of silently
//                       clamping (bounds checking; disables constexpr).

#if !defined(__cplusplus)
#error "ufloat.h requires C++ (operator overloading). A C builtin needs compiler changes."
#endif

#include <cmath> // INFINITY, std::isnan

#if defined(UFLOAT_CHECKED)
#include <cassert>
#define UFLOAT_CONSTEXPR inline // asserts are not usable in a C++11 constexpr fn
#else
#define UFLOAT_CONSTEXPR constexpr
#endif

class ufloat {
public:
  // Saturation bounds. Define UFLOAT_MAX to bound the top end.
  static constexpr float lo() noexcept { return 0.0f; }
  static constexpr float hi() noexcept {
#if defined(UFLOAT_MAX)
    return static_cast<float>(UFLOAT_MAX);
#else
    return INFINITY;
#endif
  }

  // --- construction: clamps into [lo(), hi()] ---
  constexpr ufloat() noexcept : v_(0.0f) {}
  UFLOAT_CONSTEXPR ufloat(float x) noexcept : v_(clamp_(x)) {}
  UFLOAT_CONSTEXPR ufloat(double x) noexcept : v_(clamp_(static_cast<float>(x))) {}
  UFLOAT_CONSTEXPR ufloat(int x) noexcept : v_(clamp_(static_cast<float>(x))) {}

  // --- read as a normal float (implicit -> participates in float math) ---
  constexpr operator float() const noexcept { return v_; }

  // --- writes clamp: this is the "can never be assigned < 0" guarantee ---
  // (Non-constexpr: mutating members are not constexpr until C++14, and we want
  //  C++11 compatibility. Compile-time-constant construction above IS constexpr.)
  ufloat &operator=(float x) noexcept { v_ = clamp_(x); return *this; }
  ufloat &operator+=(float x) noexcept { v_ = clamp_(v_ + x); return *this; }
  ufloat &operator-=(float x) noexcept { v_ = clamp_(v_ - x); return *this; }
  ufloat &operator*=(float x) noexcept { v_ = clamp_(v_ * x); return *this; }
  ufloat &operator/=(float x) noexcept { v_ = clamp_(v_ / x); return *this; }

private:
  static UFLOAT_CONSTEXPR float clamp_(float x) noexcept {
#if defined(UFLOAT_CHECKED)
    assert(!std::isnan(x) && "ufloat: NaN write");
    assert(x >= 0.0f && "ufloat: negative write");
#endif
    // NaN falls through both comparisons and passes unchanged (unless CHECKED).
    return x < lo() ? lo() : (x > hi() ? hi() : x);
  }
  float v_;
};

#undef UFLOAT_CONSTEXPR

// ---------------------------------------------------------------------------
// Notes on a TRUE builtin ufloat (compiler-level), for reference:
//   * Clang is the more tractable host: add a BuiltinType (BuiltinTypes.def), a
//     keyword + Sema, and CodeGen that lowers to LLVM `float`. The novel part is
//     the saturating store -- there is no scalar type today that runs code on
//     assignment, so you'd hook lvalue-store emission for this type to insert an
//     `llvm.maxnum.f32(x, 0)`. That is non-standard and surprising.
//   * Prior art for an "unsigned saturating" SCALAR that already exists: GCC's
//     `_Sat unsigned _Fract` (fixed-point, range [0,1)). It shows the concept is
//     expressible for fixed-point; float has no such standard analog.
//   * Recommended path: prototype semantics here first; only move into the
//     compiler if a header type proves insufficient (e.g. you need it in C, or
//     zero-overhead guaranteed by the type system rather than the optimizer).
// ---------------------------------------------------------------------------

#endif // UFLOAT_H_
