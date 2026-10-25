#+vet explicit-allocators
package harness

import "core:mem"

// A step is a local jump in the box-filtered luma. A visibility count changes
// the ambient in one step of 1/8 or 1/16, and that step survives as a contour
// band. The 9x9 box removes the output dither and the stochastic sample noise;
// half a level then names a band edge. The 8 level cap keeps a geometry edge
// out of the count.
STEP_BLUR :: 9
STEP_MIN_LEVELS :: 0.5
STEP_MAX_LEVELS :: 8.0

Capture_Steps_Options :: struct {
	blur: int,
	min:  f32,
	max:  f32,
}

capture_steps_default :: proc() -> Capture_Steps_Options {
	return {blur = STEP_BLUR, min = STEP_MIN_LEVELS, max = STEP_MAX_LEVELS}
}

Capture_Steps :: struct {
	count: int   `json:"count"`,
	pairs: int   `json:"pairs"`,
	max:   f32   `json:"max"`,
	blur:  int   `json:"blur"`,
	floor: f32   `json:"min"`,
	cap:   f32   `json:"max_levels"`,
}

capture_steps_build :: proc(
	values: []f32,
	width, height: u32,
	region: Capture_Region,
	options: Capture_Steps_Options,
	allocator: mem.Allocator,
) -> Capture_Steps {
	if region.w <= 1 || region.h <= 1 {
		return {}
	}
	radius := max((options.blur - 1) / 2, 0)
	rows := region.h + 2 * radius
	horizontal := make([]f32, rows * region.w, allocator)
	defer delete(horizontal, allocator)
	for row in 0 ..< rows {
		y := clamp(region.y + row - radius, 0, int(height) - 1)
		for column in 0 ..< region.w {
			x := region.x + column
			sum: f32
			for tap in -radius ..= radius {
				sample_x := clamp(x + tap, 0, int(width) - 1)
				sum += step_luma(values, int(width), sample_x, y)
			}
			horizontal[row * region.w + column] = sum
		}
	}

	blurred := make([]f32, region.w * region.h, allocator)
	defer delete(blurred, allocator)
	span := 2 * radius + 1
	scale := 1.0 / f32(span * span)
	for row in 0 ..< region.h {
		for column in 0 ..< region.w {
			sum: f32
			for tap in 0 ..< span {
				sum += horizontal[(row + tap) * region.w + column]
			}
			blurred[row * region.w + column] = sum * scale
		}
	}

	result := Capture_Steps {
		blur  = options.blur,
		floor = options.min,
		cap   = options.max,
	}
	for row in 0 ..< region.h {
		for column in 0 ..< region.w {
			index := row * region.w + column
			if column > 0 {
				jump := abs(blurred[index] - blurred[index - 1])
				result.pairs += 1
				result.max = max(result.max, jump)
				if jump > options.min && jump < options.max {
					result.count += 1
				}
			}
			if row > 0 {
				jump := abs(blurred[index] - blurred[index - region.w])
				result.pairs += 1
				result.max = max(result.max, jump)
				if jump > options.min && jump < options.max {
					result.count += 1
				}
			}
		}
	}
	return result
}

@(private)
step_luma :: proc(values: []f32, width, x, y: int) -> f32 {
	base := (y * width + x) * 4
	return (values[base] + values[base + 1] + values[base + 2]) / 3.0
}
