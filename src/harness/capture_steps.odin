#+vet explicit-allocators
package harness

import "core:mem"
import "core:slice"

// A step is a local jump in the box-filtered luma. A visibility count changes
// the ambient in one step of 1/8 or 1/16, and that step survives as a contour
// band. The 9x9 box removes the output dither and the stochastic sample noise;
// half a level then names a band edge. The 8 level cap keeps a geometry edge
// out of the count.
STEP_BLUR :: 9
STEP_MIN_LEVELS :: 0.5
STEP_MAX_LEVELS :: 8.0
STEP_TOP_JUMPS :: 8

Capture_Steps_Options :: struct {
	blur: int,
	min:  f32,
	max:  f32,
}

capture_steps_default :: proc() -> Capture_Steps_Options {
	return {blur = STEP_BLUR, min = STEP_MIN_LEVELS, max = STEP_MAX_LEVELS}
}

Step_Jump :: struct {
	x:      int    `json:"x"`,
	y:      int    `json:"y"`,
	axis:   string `json:"axis"`,
	levels: f32    `json:"levels"`,
}

Capture_Steps :: struct {
	count:    int         `json:"count"`,
	pairs:    int         `json:"pairs"`,
	max:      f32         `json:"max"`,
	over_cap: int         `json:"over_cap"`,
	blur:     int         `json:"blur"`,
	floor:    f32         `json:"min"`,
	cap:      f32         `json:"max_levels"`,
	top:      []Step_Jump `json:"top"`,
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
	top: [STEP_TOP_JUMPS]Step_Jump
	top_count := 0
	for row in 0 ..< region.h {
		for column in 0 ..< region.w {
			index := row * region.w + column
			if column > 0 {
				jump := abs(blurred[index] - blurred[index - 1])
				step_count(&result, &top, &top_count, jump, {
					x      = region.x + column,
					y      = region.y + row,
					axis   = "x",
					levels = jump,
				}, options)
			}
			if row > 0 {
				jump := abs(blurred[index] - blurred[index - region.w])
				step_count(&result, &top, &top_count, jump, {
					x      = region.x + column,
					y      = region.y + row,
					axis   = "y",
					levels = jump,
				}, options)
			}
		}
	}
	slice.sort_by(top[:top_count], proc(a, b: Step_Jump) -> bool {
		return a.levels > b.levels
	})
	result.top = make([]Step_Jump, top_count, allocator)
	copy(result.top, top[:top_count])
	return result
}

@(private)
step_count :: proc(
	steps: ^Capture_Steps,
	top: ^[STEP_TOP_JUMPS]Step_Jump,
	top_count: ^int,
	jump: f32,
	location: Step_Jump,
	options: Capture_Steps_Options,
) {
	steps.pairs += 1
	steps.max = max(steps.max, jump)
	if jump >= options.max {
		steps.over_cap += 1
		return
	}
	if jump <= options.min {
		return
	}
	steps.count += 1
	if top_count^ < STEP_TOP_JUMPS {
		top^[top_count^] = location
		top_count^ += 1
		return
	}
	smallest := 0
	for index in 1 ..< STEP_TOP_JUMPS {
		if top^[index].levels < top^[smallest].levels {
			smallest = index
		}
	}
	if jump > top^[smallest].levels {
		top^[smallest] = location
	}
}

capture_steps_destroy :: proc(steps: ^Capture_Steps, allocator: mem.Allocator) {
	if steps.top != nil {
		delete(steps.top, allocator)
	}
	steps^ = {}
}

@(private)
step_luma :: proc(values: []f32, width, x, y: int) -> f32 {
	base := (y * width + x) * 4
	return (values[base] + values[base + 1] + values[base + 2]) / 3.0
}
