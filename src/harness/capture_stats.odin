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
	velocity_median_texels: Maybe(f32) `json:"velocity_median_texels,omitempty"`,
}

capture_stats :: proc(
	values: []f32,
	width, height: u32,
	target: Capture_Target,
	allocator: mem.Allocator,
) -> Capture_Stats {
	stats := Capture_Stats {
		min = {1e30, 1e30, 1e30, 1e30},
		max = {-1e30, -1e30, -1e30, -1e30},
	}
	pixels := len(values) / 4
	if pixels == 0 {
		return stats
	}
	sums: [4]f64
	for pixel in 0 ..< pixels {
		for channel in 0 ..< 4 {
			value := values[pixel * 4 + channel]
			stats.min[channel] = min(stats.min[channel], value)
			stats.max[channel] = max(stats.max[channel], value)
			sums[channel] += f64(value)
		}
	}
	for channel in 0 ..< 4 {
		stats.mean[channel] = f32(sums[channel] / f64(pixels))
	}
	if target == .Velocity {
		lengths := make([]f32, pixels, allocator)
		defer delete(lengths, allocator)
		covered := 0
		for pixel in 0 ..< pixels {
			depth := values[pixel * 4 + 2]
			if depth <= 0 || depth >= renderer.CAMERA_FAR {
				continue
			}
			x := values[pixel * 4 + 0] * f32(width)
			y := values[pixel * 4 + 1] * f32(height)
			lengths[covered] = math.sqrt(x * x + y * y)
			covered += 1
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
