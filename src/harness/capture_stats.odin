#+vet explicit-allocators
package harness

import "core:math"
import "core:mem"
import "core:slice"

import "src:digest"
import "src:renderer"

// The report names the four channels, so a reader does not have to know that
// index 1 is green.
Capture_Channels :: struct {
	x: f32 `json:"x"`,
	y: f32 `json:"y"`,
	z: f32 `json:"z"`,
	w: f32 `json:"w"`,
}

Capture_Stats :: struct {
	min:                    Capture_Channels `json:"min"`,
	max:                    Capture_Channels `json:"max"`,
	mean:                   Capture_Channels `json:"mean"`,
	stddev:                 Capture_Channels `json:"stddev"`,
	gradient:               Capture_Channels `json:"gradient"`,
	color_key:              Maybe(Capture_Color_Key_Result) `json:"color_key,omitempty"`,
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
	color_key: Maybe(Capture_Color_Key),
	allocator: mem.Allocator,
) -> Capture_Stats {
	stats: Capture_Stats
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
	minima := [4]f32{1e30, 1e30, 1e30, 1e30}
	maxima := [4]f32{-1e30, -1e30, -1e30, -1e30}
	pairs := 0
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			base := (y * int(width) + x) * 4
			for channel in 0 ..< 4 {
				value := values[base + channel]
				minima[channel] = min(minima[channel], value)
				maxima[channel] = max(maxima[channel], value)
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
	means: [4]f32
	stddevs: [4]f32
	gradients: [4]f32
	for channel in 0 ..< 4 {
		mean := sums[channel] / f64(count)
		variance := squares[channel] / f64(count) - mean * mean
		means[channel] = f32(mean)
		stddevs[channel] = f32(math.sqrt(max(variance, 0)))
		if pairs > 0 {
			gradients[channel] = f32(gradient_sums[channel] / f64(pairs))
		}
	}
	stats.min = stats_channels(minima)
	stats.max = stats_channels(maxima)
	stats.mean = stats_channels(means)
	stats.stddev = stats_channels(stddevs)
	stats.gradient = stats_channels(gradients)
	if key, has_key := color_key.?; has_key {
		stats.color_key = capture_color_key_build(values, width, height, region, key)
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

@(private)
stats_channels :: proc(values: [4]f32) -> Capture_Channels {
	return {x = values[0], y = values[1], z = values[2], w = values[3]}
}

// The check resolver names a channel, so one helper maps the JSON name to the
// struct field.
capture_channel_value :: proc(channels: Capture_Channels, axis: string) -> (f32, bool) {
	switch axis {
	case "x":
		return channels.x, true
	case "y":
		return channels.y, true
	case "z":
		return channels.z, true
	case "w":
		return channels.w, true
	}
	return 0, false
}

pixel_hash :: proc(pixels: []u8, allocator: mem.Allocator) -> string {
	hash := digest.fnv()
	digest.write_bytes(&hash, pixels)
	return digest.hex(hash, allocator)
}
