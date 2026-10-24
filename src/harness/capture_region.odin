#+vet explicit-allocators
package harness


import "core:mem"

// A region limits the statistics to a rectangle of the source image. The short
// `rect: [x, y, w, h]` form and the object form describe the same thing.
Capture_Region :: struct {
	x: int `json:"x"`,
	y: int `json:"y"`,
	w: int `json:"w"`,
	h: int `json:"h"`,
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
