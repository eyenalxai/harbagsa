#+vet explicit-allocators
package harness


import "core:math"
import "core:mem"

// A region limits the statistics to a rectangle of the source image. The short
// `rect: [x, y, w, h]` form and the object form describe the same thing.
Capture_Region :: struct {
	x: int `json:"x"`,
	y: int `json:"y"`,
	w: int `json:"w"`,
	h: int `json:"h"`,
}

Capture_Region_Unit :: enum {
	Pixels,
	Normalized,
}

// A scenario names a region before the capture extent is known. A normalized
// region resolves against the frame it reads, so one file works at every size.
Capture_Region_Spec :: struct {
	unit:       Capture_Region_Unit,
	pixels:     Capture_Region,
	normalized: [4]f32,
}

capture_region_spec_pixels :: proc(region: Capture_Region) -> Capture_Region_Spec {
	return {unit = .Pixels, pixels = region}
}

capture_region_resolve :: proc(
	spec: Capture_Region_Spec,
	width, height: u32,
) -> (Capture_Region, string) {
	if spec.unit == .Pixels {
		region := spec.pixels
		if !capture_region_valid(region, width, height) {
			return {}, format_error("region must be inside the %dx%d target", width, height)
		}
		return region, ""
	}
	x, y, w, h := spec.normalized[0], spec.normalized[1], spec.normalized[2], spec.normalized[3]
	if x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > 1.000001 || y + h > 1.000001 {
		return {}, format_error(
			"a normalized region needs x, y in [0, 1], positive w, h, and x+w, y+h at most 1",
		)
	}
	left := int(math.round(f64(x) * f64(width)))
	top := int(math.round(f64(y) * f64(height)))
	right := int(math.round(f64(x + w) * f64(width)))
	bottom := int(math.round(f64(y + h) * f64(height)))
	left = clamp(left, 0, int(width) - 1)
	top = clamp(top, 0, int(height) - 1)
	right = clamp(right, left + 1, int(width))
	bottom = clamp(bottom, top + 1, int(height))
	return {x = left, y = top, w = right - left, h = bottom - top}, ""
}

Profile_Axis :: enum {
	X,
	Y,
}

Profile_Channel :: enum {
	Luma,
	X,
	Y,
	Z,
}

Capture_Crop :: struct {
	x:     int,
	y:     int,
	w:     int,
	h:     int,
	scale: int,
}

Capture_Histogram :: struct {
	bins: int,
}

Capture_Profile_Result :: struct {
	axis:      string `json:"axis"`,
	at:        int    `json:"at"`,
	from:      int    `json:"from"`,
	to:        int    `json:"to"`,
	channel:   string `json:"channel"`,
	source:    string `json:"source"`,
	mean:      bool   `json:"mean"`,
	values:    []f32  `json:"values"`,
	width:     f32    `json:"width"`,
	low_index: int    `json:"low_index"`,
	high_index: int   `json:"high_index"`,
	flat:      bool   `json:"flat"`,
}

Capture_Crop_Result :: struct {
	x:      int `json:"x"`,
	y:      int `json:"y"`,
	w:      int `json:"w"`,
	h:      int `json:"h"`,
	scale:  int `json:"scale"`,
	width:  u32 `json:"width"`,
	height: u32 `json:"height"`,
}

Capture_Histogram_Result :: struct {
	bins: int   `json:"bins"`,
	x:    []int `json:"x"`,
	y:    []int `json:"y"`,
	z:    []int `json:"z"`,
	w:    []int `json:"w"`,
}

profile_axis_name :: proc(axis: Profile_Axis) -> string {
	return axis == .X ? "x" : "y"
}

profile_axis_parse :: proc(name: string) -> (Profile_Axis, bool) {
	switch name {
	case "x":
		return .X, true
	case "y":
		return .Y, true
	}
	return .X, false
}

profile_channel_name :: proc(channel: Profile_Channel) -> string {
	switch channel {
	case .Luma:
		return "luma"
	case .X:
		return "x"
	case .Y:
		return "y"
	case .Z:
		return "z"
	}
	return "luma"
}

profile_channel_parse :: proc(name: string) -> (Profile_Channel, bool) {
	switch name {
	case "luma":
		return .Luma, true
	case "x":
		return .X, true
	case "y":
		return .Y, true
	case "z":
		return .Z, true
	}
	return .Luma, false
}

capture_region_valid :: proc(region: Capture_Region, width, height: u32) -> bool {
	return region.x >= 0 &&
		region.y >= 0 &&
		region.w > 0 &&
		region.h > 0 &&
		region.x + region.w <= int(width) &&
		region.y + region.h <= int(height)
}

capture_crop_valid :: proc(crop: Capture_Crop, width, height: u32) -> bool {
	return crop.scale >= 1 &&
		crop.scale <= 8 &&
		crop.x >= 0 &&
		crop.y >= 0 &&
		crop.w > 0 &&
		crop.h > 0 &&
		crop.x + crop.w <= int(width) &&
		crop.y + crop.h <= int(height)
}

capture_crop_pixels :: proc(
	pixels: []u8,
	width, height: u32,
	crop: Capture_Crop,
	allocator: mem.Allocator,
) -> (
	[]u8,
	u32,
	u32,
	string,
) {
	if !capture_crop_valid(crop, width, height) {
		return nil, 0, 0, format_error("crop must be inside the target with a scale in [1, 8]")
	}
	out_width := u32(crop.w * crop.scale)
	out_height := u32(crop.h * crop.scale)
	out := make([]u8, int(out_width * out_height * 4), allocator)
	for y in 0 ..< int(out_height) {
		source_y := crop.y + y / crop.scale
		for x in 0 ..< int(out_width) {
			source_x := crop.x + x / crop.scale
			source := (source_y * int(width) + source_x) * 4
			target := (y * int(out_width) + x) * 4
			copy(out[target:target + 4], pixels[source:source + 4])
		}
	}
	return out, out_width, out_height, ""
}

capture_histogram_build :: proc(
	pixels: []u8,
	width: u32,
	region: Capture_Region,
	bins: int,
	allocator: mem.Allocator,
) -> Capture_Histogram_Result {
	result := Capture_Histogram_Result {
		bins = bins,
		x = make([]int, bins, allocator),
		y = make([]int, bins, allocator),
		z = make([]int, bins, allocator),
		w = make([]int, bins, allocator),
	}
	for y in region.y ..< region.y + region.h {
		for x in region.x ..< region.x + region.w {
			base := (y * int(width) + x) * 4
			if base + 3 >= len(pixels) {
				continue
			}
			for channel in 0 ..< 4 {
				bin := clamp(int(pixels[base + channel]) * bins / 256, 0, bins - 1)
				switch channel {
				case 0:
					result.x[bin] += 1
				case 1:
					result.y[bin] += 1
				case 2:
					result.z[bin] += 1
				case 3:
					result.w[bin] += 1
				}
			}
		}
	}
	return result
}

capture_profile_destroy :: proc(profile: ^Capture_Profile_Result, allocator: mem.Allocator) {
	if profile.values != nil {
		delete(profile.values, allocator)
	}
	profile^ = {}
}

capture_histogram_destroy :: proc(histogram: ^Capture_Histogram_Result, allocator: mem.Allocator) {
	delete(histogram.x, allocator)
	delete(histogram.y, allocator)
	delete(histogram.z, allocator)
	delete(histogram.w, allocator)
	histogram^ = {}
}
