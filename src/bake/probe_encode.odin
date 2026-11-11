#+vet explicit-allocators
package bake

import "core:math"

// VK_FORMAT_B10G11R11_UFLOAT_PACK32: red in the low 11 bits, green in the next
// 11, and blue in the high 10. Each channel has a 5-bit exponent and no sign.
@(private)
pack_r11g11b10 :: proc(value: [3]f64) -> u32 {
	red := pack_unsigned_float(value[0], 6)
	green := pack_unsigned_float(value[1], 6)
	blue := pack_unsigned_float(value[2], 5)
	return red | green << 11 | blue << 22
}

@(private)
pack_unsigned_float :: proc(value: f64, mantissa_bits: int) -> u32 {
	if !(value > 0) || value != value {
		return 0
	}
	shift := uint(mantissa_bits)
	max_mantissa := (u32(1) << shift) - 1
	max_value := (2.0 - 1.0 / f64(u32(1) << shift)) * 32768.0
	max_encoding := u32(30) << shift | max_mantissa
	if value >= max_value {
		return max_encoding
	}
	fraction, exponent := math.frexp(value)
	biased := exponent + 14
	if biased <= 0 {
		scaled := value * 16384.0 * f64(u32(1) << shift)
		mantissa := u32(math.floor(scaled + 0.5))
		if mantissa > max_mantissa {
			return u32(1) << shift
		}
		return mantissa
	}
	mantissa := u32(math.floor((fraction * 2.0 - 1.0) * f64(u32(1) << shift) + 0.5))
	if mantissa > max_mantissa {
		mantissa = 0
		biased += 1
	}
	if biased >= 31 {
		return max_encoding
	}
	return u32(biased) << shift | mantissa
}
