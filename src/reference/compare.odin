#+vet explicit-allocators
package reference

import "core:math"
import "core:mem"
import "core:slice"

// The comparison pairs the path-traced indirect term with the probe field's
// indirect term. `gpu` is the difference of two `scene_color` frames that
// differ only in the gather toggle, so the direct light cancels exactly:
//
//   gpu     = gi_on - gi_off = albedo * probe_indirect
//   sample  = albedo * mean_cos(next radiance)
//
// Both sides are the cosine-weighted mean of the light that arrives at the
// surface, so the ratio is the probe field's error, not a scale convention.

DARK_LUMA :: f32(1e-5)

Tolerance :: struct {
	ratio_min:        f32 `json:"ratio_min"`,
	ratio_max:        f32 `json:"ratio_max"`,
	error_max:        f32 `json:"error_max"`,
	colour_max:       f32 `json:"colour_max"`,
	zero_fraction_max: f32 `json:"zero_fraction_max"`,
}

Point :: struct {
	x:         int    `json:"x"`,
	y:         int    `json:"y"`,
	box:       int    `json:"box"`,
	reference: [3]f32 `json:"reference"`,
	gpu:       [3]f32 `json:"gpu"`,
	ratio:     f32    `json:"ratio"`,
	error:     f32    `json:"error"`,
}

Metrics :: struct {
	points:         int    `json:"points"`,
	sky:            int    `json:"sky"`,
	edge:           int    `json:"edge"`,
	dark:           int    `json:"dark"`,
	zero:           int    `json:"zero"`,
	zero_fraction:  f32    `json:"zero_fraction"`,
	ratio:          f32    `json:"ratio"`,
	ratio_p10:      f32    `json:"ratio_p10"`,
	ratio_p90:      f32    `json:"ratio_p90"`,
	error:          f32    `json:"error"`,
	energy:         [3]f32 `json:"energy"`,
	colour_spread:  f32    `json:"colour_spread"`,
	mean_reference: f32    `json:"mean_reference"`,
	mean_gpu:       f32    `json:"mean_gpu"`,
	direct_points:  int    `json:"direct_points"`,
	direct_ratio:   f32    `json:"direct_ratio"`,
	direct_error:   f32    `json:"direct_error"`,
}

Comparison :: struct {
	points:  []Point,
	metrics: Metrics,
}

Comparison_Destroy :: proc(comparison: ^Comparison, allocator: mem.Allocator) {
	delete(comparison.points, allocator)
	comparison^ = {}
}

luma :: proc(rgb: [3]f32) -> f32 {
	return 0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
}

median :: proc(values: []f32) -> f32 {
	if len(values) == 0 {
		return 0
	}
	middle := len(values) / 2
	if len(values) % 2 == 1 {
		return values[middle]
	}
	return (values[middle - 1] + values[middle]) * 0.5
}

percentile :: proc(values: []f32, fraction: f32) -> f32 {
	if len(values) == 0 {
		return 0
	}
	index := clamp(int(fraction * f32(len(values) - 1) + 0.5), 0, len(values) - 1)
	return values[index]
}

// `gpu_gi` and `gpu_direct` hold RGBA f32 values in row-major pixel order, as a
// `scene_color` float capture writes them.
compare :: proc(
	gpu_gi, gpu_direct: []f32,
	frame_width, frame_height: u32,
	grid: Grid,
	allocator: mem.Allocator,
) -> Comparison {
	points := make([dynamic]Point, 0, len(grid.samples), allocator)
	ratios := make([dynamic]f32, 0, len(grid.samples), allocator)
	defer delete(ratios)
	errors := make([dynamic]f32, 0, len(grid.samples), allocator)
	defer delete(errors)
	direct_ratios := make([dynamic]f32, 0, len(grid.samples), allocator)
	defer delete(direct_ratios)
	direct_errors := make([dynamic]f32, 0, len(grid.samples), allocator)
	defer delete(direct_errors)
	energy_gpu := [3]f32{}
	energy_reference := [3]f32{}
	reference_sum: f32
	gpu_sum: f32
	sky, edge, dark, zero := 0, 0, 0, 0

	for sample in grid.samples {
		if sample.sky {
			sky += 1
			continue
		}
		if sample.edge {
			edge += 1
			continue
		}
		pixel := (sample.y * int(frame_width) + sample.x) * 4
		if pixel + 3 >= len(gpu_gi) || pixel + 3 >= len(gpu_direct) {
			continue
		}
		reference := sample.indirect
		reference_luma := luma(reference)
		if reference_luma < DARK_LUMA {
			dark += 1
			continue
		}
		gpu := [3]f32{
			max(gpu_gi[pixel + 0] - gpu_direct[pixel + 0], 0.0),
			max(gpu_gi[pixel + 1] - gpu_direct[pixel + 1], 0.0),
			max(gpu_gi[pixel + 2] - gpu_direct[pixel + 2], 0.0),
		}
		gpu_luma := luma(gpu)
		if gpu_luma <= DARK_LUMA {
			zero += 1
		}
		ratio := gpu_luma / reference_luma
		error := abs(gpu_luma - reference_luma) / reference_luma
		append(&ratios, ratio)
		append(&errors, error)
		append(&points, Point {
			x = sample.x,
			y = sample.y,
			box = sample.box,
			reference = reference,
			gpu = gpu,
			ratio = ratio,
			error = error,
		})
		for channel in 0 ..< 3 {
			energy_gpu[channel] += gpu[channel]
			energy_reference[channel] += reference[channel]
		}
		reference_sum += reference_luma
		gpu_sum += gpu_luma

		// The direct term validates the estimator itself: it is the lamp and
		// the sun with hard shadows, which a path tracer reproduces exactly.
		// Emissive faces are skipped because the lit pass adds the emission to
		// the same pixel.
		direct_luma := luma(
			{
				gpu_direct[pixel + 0],
				gpu_direct[pixel + 1],
				gpu_direct[pixel + 2],
			},
		)
		reference_direct := luma(sample.direct)
		if luma(sample.emission) == 0 && reference_direct >= DARK_LUMA && direct_luma > 0 {
			append(&direct_ratios, direct_luma / reference_direct)
			append(&direct_errors, abs(direct_luma - reference_direct) / reference_direct)
		}
	}

	metrics := Metrics{points = len(points), sky = sky, edge = edge, dark = dark, zero = zero}
	if len(points) > 0 {
		metrics.zero_fraction = f32(zero) / f32(len(points))
		slice.sort(ratios[:])
		slice.sort(errors[:])
		metrics.ratio = median(ratios[:])
		metrics.ratio_p10 = percentile(ratios[:], 0.10)
		metrics.ratio_p90 = percentile(ratios[:], 0.90)
		metrics.error = median(errors[:])
		metrics.mean_reference = reference_sum / f32(len(points))
		metrics.mean_gpu = gpu_sum / f32(len(points))
		if len(direct_ratios) > 0 {
			slice.sort(direct_ratios[:])
			slice.sort(direct_errors[:])
			metrics.direct_points = len(direct_ratios)
			metrics.direct_ratio = median(direct_ratios[:])
			metrics.direct_error = median(direct_errors[:])
		}
		low: f32 = math.F32_MAX
		high: f32 = 0
		for channel in 0 ..< 3 {
			ratio := energy_gpu[channel] / energy_reference[channel] if energy_reference[channel] > 0 else 0
			metrics.energy[channel] = ratio
			low = min(low, ratio)
			high = max(high, ratio)
		}
		metrics.colour_spread = high - low
	}
	return {points = points[:], metrics = metrics}
}

metrics_within :: proc(metrics: Metrics, tolerance: Tolerance) -> bool {
	if metrics.points == 0 {
		return false
	}
	if metrics.ratio < tolerance.ratio_min || metrics.ratio > tolerance.ratio_max {
		return false
	}
	if metrics.error > tolerance.error_max {
		return false
	}
	if metrics.colour_spread > tolerance.colour_max {
		return false
	}
	return metrics.zero_fraction <= tolerance.zero_fraction_max
}
