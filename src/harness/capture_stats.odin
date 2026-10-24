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

// A region limits the statistics to a rectangle; the whole image stays the
// default. The caller validates the bounds against the capture extent.
capture_stats :: proc(
	values: []f32,
	width, height: u32,
	target: Capture_Target,
	region: Maybe(Capture_Region),
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
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			base := (y * int(width) + x) * 4
			for channel in 0 ..< 4 {
				value := values[base + channel]
				stats.min[channel] = min(stats.min[channel], value)
				stats.max[channel] = max(stats.max[channel], value)
				sums[channel] += f64(value)
			}
		}
	}
	for channel in 0 ..< 4 {
		stats.mean[channel] = f32(sums[channel] / f64(count))
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
