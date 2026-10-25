#+vet explicit-allocators
package harness

import "core:math"
import "core:mem"
import "core:slice"

import "src:digest"
import "src:renderer"

Capture_Stats :: struct {
	min:                    [4]f32 `json:"min"`,
	max:                    [4]f32 `json:"max"`,
	mean:                   [4]f32 `json:"mean"`,
	stddev:                 [4]f32 `json:"stddev"`,
	gradient:               [4]f32 `json:"gradient"`,
	steps:                  Maybe(Capture_Steps) `json:"steps,omitempty"`,
	velocity_median_texels: Maybe(f32) `json:"velocity_median_texels,omitempty"`,
}

// A region limits the statistics to a rectangle; the whole image stays the
// default. The caller validates the bounds against the capture extent.
capture_stats :: proc(
	values: []f32,
	width, height: u32,
	target: Capture_Target,
	region: Maybe(Capture_Region),
	steps: Maybe(Capture_Steps_Options),
	allocator: mem.Allocator,
) -> Capture_Stats {
	stats := Capture_Stats {
		min = {1e30, 1e30, 1e30, 1e30},
		max = {-1e30, -1e30, -1e30, -1e30},
	}
	x0, y0, x1, y1 := 0, 0, int(width), int(height)
	if bounds, has_region := region.?; has_region {
		x0, y0 = bounds.x, bounds.y
		x1, y1 = bounds.x + bounds.w, bounds.y + bounds.h
	}
	count := (x1 - x0) * (y1 - y0)
	if count <= 0 {
		return stats
	}
	sums: [4]f64
	squares: [4]f64
	gradient_sums: [4]f64
	pairs := 0
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			base := (y * int(width) + x) * 4
			for channel in 0 ..< 4 {
				value := values[base + channel]
				stats.min[channel] = min(stats.min[channel], value)
				stats.max[channel] = max(stats.max[channel], value)
				sums[channel] += f64(value)
				squares[channel] += f64(value) * f64(value)
			}
			// Compare with the left and top neighbours, so each pair counts once.
			if x > x0 {
				left := base - 4
				for channel in 0 ..< 4 {
					gradient_sums[channel] += f64(abs(values[base + channel] - values[left + channel]))
				}
				pairs += 1
			}
			if y > y0 {
				up := base - int(width) * 4
				for channel in 0 ..< 4 {
					gradient_sums[channel] += f64(abs(values[base + channel] - values[up + channel]))
				}
				pairs += 1
			}
		}
	}
	for channel in 0 ..< 4 {
		mean := sums[channel] / f64(count)
		variance := squares[channel] / f64(count) - mean * mean
		stats.mean[channel] = f32(mean)
		stats.stddev[channel] = f32(math.sqrt(max(variance, 0)))
		if pairs > 0 {
			stats.gradient[channel] = f32(gradient_sums[channel] / f64(pairs))
		}
	}
	if bounds, has_region := region.?; has_region {
		options := capture_steps_default()
		if configured, has_steps := steps.?; has_steps {
			options = configured
		}
		stats.steps = capture_steps_build(values, width, height, bounds, options, allocator)
	}
	if target == .Velocity {
		lengths := make([]f32, count, allocator)
		defer delete(lengths, allocator)
		covered := 0
		for y in y0 ..< y1 {
			for x in x0 ..< x1 {
				base := (y * int(width) + x) * 4
				depth := values[base + 2]
				if depth <= 0 || depth >= renderer.CAMERA_FAR {
					continue
				}
				dx := values[base + 0] * f32(width)
				dy := values[base + 1] * f32(height)
				lengths[covered] = math.sqrt(dx * dx + dy * dy)
				covered += 1
			}
		}
		if covered > 0 {
			slice.sort(lengths[:covered])
			stats.velocity_median_texels = lengths[covered / 2]
		} else {
			stats.velocity_median_texels = 0
		}
	}
	return stats
}

pixel_hash :: proc(pixels: []u8, allocator: mem.Allocator) -> string {
	hash := digest.fnv()
	digest.write_bytes(&hash, pixels)
	return digest.hex(hash, allocator)
}
