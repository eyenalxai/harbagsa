#+vet explicit-allocators
package harness

import "core:math"
import "core:mem"

// A profile runs along one axis at a fixed coordinate on the other. `mean`
// averages the whole perpendicular span instead, so a gradient can be read
// without choosing a row.
Capture_Profile :: struct {
	axis:    Profile_Axis,
	channel: Profile_Channel,
	at:      int,
	from:    int,
	to:      int,
	mean:    bool,
	low:     f32,
	high:    f32,
	has_low: bool,
	has_high: bool,
}

// The PNG paths are 8-bit sRGB, so a profile decodes each channel before it
// measures a gradient.
srgb_byte_to_linear :: proc(value: u8) -> f32 {
	c := f32(value) / 255.0
	if c <= 0.04045 {
		return c / 12.92
	}
	return math.pow((c + 0.055) / 1.055, 2.4)
}

capture_profile_build :: proc(
	pixels: []u8,
	width, height: u32,
	spec: Capture_Profile,
	allocator: mem.Allocator,
) -> (
	Capture_Profile_Result,
	string,
) {
	run_extent := spec.axis == .X ? int(width) : int(height)
	fixed_extent := spec.axis == .X ? int(height) : int(width)
	if spec.from < 0 || spec.to < spec.from || spec.to >= run_extent {
		return {}, format_error(
			"profile range must be inside [0, %d]",
			run_extent - 1,
		)
	}
	if !spec.mean && (spec.at < 0 || spec.at >= fixed_extent) {
		return {}, format_error(
			"profile 'at' must be inside [0, %d]",
			fixed_extent - 1,
		)
	}
	length := spec.to - spec.from + 1
	values := make([]f32, length, allocator)
	for index in 0 ..< length {
		position := spec.from + index
		if spec.mean {
			total: f32
			for other in 0 ..< fixed_extent {
				x := spec.axis == .X ? position : other
				y := spec.axis == .X ? other : position
				total += capture_channel_value(pixels, int(width), x, y, spec.channel)
			}
			values[index] = total / f32(max(fixed_extent, 1))
		} else {
			x := spec.axis == .X ? position : spec.at
			y := spec.axis == .X ? spec.at : position
			values[index] = capture_channel_value(pixels, int(width), x, y, spec.channel)
		}
	}
	result := capture_profile_summary(values, spec)
	result.axis = profile_axis_name(spec.axis)
	result.at = spec.at
	result.from = spec.from
	result.to = spec.to
	result.channel = profile_channel_name(spec.channel)
	result.mean = spec.mean
	return result, ""
}

@(private)
capture_channel_value :: proc(
	pixels: []u8,
	width, x, y: int,
	channel: Profile_Channel,
) -> f32 {
	base := (y * width + x) * 4
	if base + 3 >= len(pixels) {
		return 0
	}
	r := srgb_byte_to_linear(pixels[base])
	g := srgb_byte_to_linear(pixels[base + 1])
	b := srgb_byte_to_linear(pixels[base + 2])
	switch channel {
	case .Luma:
		return 0.2126 * r + 0.7152 * g + 0.0722 * b
	case .X:
		return r
	case .Y:
		return g
	case .Z:
		return b
	}
	return 0
}

// The 10%-90% crossing width over the span's own minimum and maximum. A flat
// span reports a zero width and sets `flat`, so a check can tell "no edge"
// from "a one-pixel edge".
capture_profile_summary :: proc(values: []f32, spec: Capture_Profile) -> Capture_Profile_Result {
	result := Capture_Profile_Result{values = values}
	if len(values) == 0 {
		result.flat = true
		return result
	}
	lowest := values[0]
	highest := values[0]
	for value in values {
		lowest = min(lowest, value)
		highest = max(highest, value)
	}
	if highest - lowest <= 1e-6 {
		result.flat = true
		return result
	}
	low_fraction := spec.has_low ? spec.low : 0.1
	high_fraction := spec.has_high ? spec.high : 0.9
	low_threshold := lowest + clamp(low_fraction, 0, 1) * (highest - lowest)
	high_threshold := lowest + clamp(high_fraction, 0, 1) * (highest - lowest)
	result.low_index = -1
	result.high_index = -1
	for value, index in values {
		if result.low_index < 0 && value >= low_threshold {
			result.low_index = index
		}
		if value >= high_threshold {
			result.high_index = index
			break
		}
	}
	if result.low_index < 0 || result.high_index < 0 || result.high_index <= result.low_index {
		result.flat = true
		result.low_index = max(result.low_index, 0)
		result.high_index = max(result.high_index, 0)
		return result
	}
	result.width = f32(result.high_index - result.low_index)
	return result
}

