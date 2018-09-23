#ifndef H_CYLGOM
#define H_CYLGOM

#include <stdbool.h>
#include <stdint.h>

// typedefs for convenience and optimizations

// 0 to save ram and optimize for embedded systems
// 1 to gain extra speed by replacing all floats by doubles
// 2 to gain extra speed by using bigger integers depending on arch
// level 2 includes *heavy* optimizations that will definitely eat your ram
#define SPEED 0

///////////////////
// regular stuff //
///////////////////

// 100% standard
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;

// float and double are not fixed-size by the C standard
// however, the C standard strongly suggests using IEEE 754
// in IEEE 754, float is 32 bits and double 64 bits
// howevevr, long double is whatever size the compiler prefers
// this is why we redefine float and double but not long double
typedef float f32;
typedef double f64;

///////////////////////////////
// black magic optimizations //
///////////////////////////////

// the best optimization out there
// doubles are usually slower than floats for various reasons
// on embedded systems though, it is usually the opposite
#if SPEED > 0
typedef f64 f32;
#endif

// the following block tries to optimize speed at the cost of ram
// we are testing the architecturee in the most portable way possible
// the following macro is not mandatory, obscure systems might not provide it
// on 16 bits systems, 16-bit integer operations can be the fastest
// on 32 bits systems, 32-bit integer operations can be the fastest
// on 64 bits systems, 64-bit integer operations can be the fastest
#if SPEED > 1
#if UINTPTR_MAX == 0xffff
typedef uint16_t u8;
typedef int16_t i8;
#elif UINTPTR_MAX == 0xffffffff
typedef uint32_t u8;
typedef int32_t i8;
typedef uint32_t u16;
typedef int32_t i16;
#elif UINTPTR_MAX == 0xffffffffffffffff
typedef uint64_t u8;
typedef int64_t i8;
typedef uint64_t u16;
typedef int64_t i16;
typedef uint64_t u32;
typedef int64_t i32;
#endif
#endif

#endif
