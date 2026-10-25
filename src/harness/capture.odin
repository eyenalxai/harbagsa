#+vet explicit-allocators
package harness

import "core:mem"

import "src:renderer"

Capture_Target :: renderer.Capture_Target

Capture_Format :: enum {
	Png,
	Float,
	Raw,
	Stats,
	Profile,
}

Capture_Format_Info :: struct {
	name:      string,
	extension: string,
}

// One row per format. The name, the parser, and the extension read this table.
CAPTURE_FORMAT_INFO := [Capture_Format]Capture_Format_Info {
	.Png = {name = "png", extension = ".png"},
	.Float = {name = "float", extension = ".f32"},
	.Raw = {name = "raw", extension = ".bin"},
	.Stats = {name = "stats"},
	.Profile = {name = "profile"},
}

capture_format_name :: proc(format: Capture_Format) -> string {
	if int(format) < 0 || int(format) >= len(CAPTURE_FORMAT_INFO) {
		return "png"
	}
	return CAPTURE_FORMAT_INFO[format].name
}

capture_format_parse :: proc(name: string) -> (format: Capture_Format, ok: bool) {
	for candidate in Capture_Format {
		if CAPTURE_FORMAT_INFO[candidate].name == name {
			return candidate, true
		}
	}
	return .Png, false
}

capture_format_extension :: proc(format: Capture_Format) -> string {
	return CAPTURE_FORMAT_INFO[format].extension
}

// The fields a command, a request, and a pending capture share. One
// declaration, so a new capture option is one field and one parser block.
Capture_Spec :: struct {
	name:      string,
	note:      string,
	target:    Capture_Target,
	format:    Capture_Format,
	png:       bool,
	region:    Maybe(Capture_Region_Spec),
	profile:   Maybe(Capture_Profile),
	crop:      Maybe(Capture_Crop),
	histogram: Maybe(int),
	steps:     Maybe(Capture_Steps_Options),
	color_key: Maybe(Capture_Color_Key),
}

Capture_Request :: struct {
	using spec: Capture_Spec,
	alpha:      f32,
}

Capture_Result :: struct {
	name:          string         `json:"name"`,
	note:          string         `json:"note,omitempty"`,
	path:          string         `json:"path,omitempty"`,
	frame:         int            `json:"frame"`,
	width:         u32            `json:"width"`,
	height:        u32            `json:"height"`,
	target:        string         `json:"target"`,
	format:        string         `json:"format"`,
	target_format: string         `json:"target_format"`,
	png:           bool           `json:"png,omitempty"`,
	hash:          string         `json:"hash,omitempty"`,
	render_digest: string         `json:"render_digest,omitempty"`,
	renderer:      renderer.Renderer_Report `json:"renderer"`,
	stats:         Maybe(Capture_Stats) `json:"stats,omitempty"`,
	region:        Maybe(Capture_Region) `json:"region,omitempty"`,
	profile:       Maybe(Capture_Profile_Result) `json:"profile,omitempty"`,
	crop:          Maybe(Capture_Crop_Result) `json:"crop,omitempty"`,
	histogram:     Maybe(Capture_Histogram_Result) `json:"histogram,omitempty"`,
	written_width:  u32 `json:"written_width,omitempty"`,
	written_height: u32 `json:"written_height,omitempty"`,
	delta_mean:    f32            `json:"delta_mean"`,
	delta_max:     u8             `json:"delta_max"`,
	delta_over_16: int            `json:"delta_over_16"`,
}

Capture_Delta :: struct {
	mean:      f32,
	max:       u8,
	over_16:   int,
	different: int,
}

// A capture writes a PNG when its format is png, or when it asks for a sidecar
// beside its stats or profile.
capture_has_png :: proc(capture: Capture_Result) -> bool {
	return capture.path != "" && (capture.format == "png" || capture.png)
}

Capture_Summary :: struct {
	count:                  int,
	worst_mean_delta:       f32,
	worst_max_delta:        u8,
	worst_over_16:          int,
	worst_over_16_fraction: f32,
	last_target:            string,
	last_format:            string,
	last_png:               bool,
	last_stats:             Maybe(Capture_Stats),
	last_profile:           Maybe(Capture_Profile_Result),
	last_region:            Maybe(Capture_Region),
	last_crop:              Maybe(Capture_Crop_Result),
	last_histogram:         Maybe(Capture_Histogram_Result),
}

capture_summary :: proc(captures: []Capture_Result) -> Capture_Summary {
	summary := Capture_Summary{count = len(captures)}
	for capture in captures {
		summary.worst_mean_delta = max(summary.worst_mean_delta, capture.delta_mean)
		summary.worst_max_delta = max(summary.worst_max_delta, capture.delta_max)
		summary.worst_over_16 = max(summary.worst_over_16, capture.delta_over_16)
		pixels := f32(capture.width) * f32(capture.height)
		if pixels > 0 {
			summary.worst_over_16_fraction = max(
				summary.worst_over_16_fraction,
				f32(capture.delta_over_16) / pixels,
			)
		}
	}
	if len(captures) > 0 {
		last := captures[len(captures) - 1]
		summary.last_target = last.target
		summary.last_format = last.format
		summary.last_png = last.png
		summary.last_stats = last.stats
		summary.last_profile = last.profile
		summary.last_region = last.region
		summary.last_crop = last.crop
		summary.last_histogram = last.histogram
	}
	return summary
}

capture_delta :: proc(previous, current: []u8) -> Capture_Delta {
	count := min(len(previous), len(current)) / 4
	if count == 0 {
		return {}
	}
	total: u64
	highest: u8
	over_16: int
	different: int
	for index in 0 ..< count {
		base := index * 4
		delta := abs(i32(current[base]) - i32(previous[base]))
		delta = max(delta, abs(i32(current[base + 1]) - i32(previous[base + 1])))
		delta = max(delta, abs(i32(current[base + 2]) - i32(previous[base + 2])))
		total += u64(delta)
		if delta > 0 {
			different += 1
		}
		if delta > 16 {
			over_16 += 1
		}
		if delta > i32(highest) {
			highest = u8(delta)
		}
	}
	return {
		mean = f32(total) / f32(count),
		max = highest,
		over_16 = over_16,
		different = different,
	}
}

capture_result_destroy :: proc(result: ^Capture_Result, allocator: mem.Allocator) {
	if result.name != "" {
		delete(result.name, allocator)
	}
	if result.note != "" {
		delete(result.note, allocator)
	}
	if result.path != "" {
		delete(result.path, allocator)
	}
	if result.hash != "" {
		delete(result.hash, allocator)
	}
	if result.render_digest != "" {
		delete(result.render_digest, allocator)
	}
	if profile, has_profile := result.profile.?; has_profile {
		capture_profile_destroy(&profile, allocator)
	}
	if histogram, has_histogram := result.histogram.?; has_histogram {
		capture_histogram_destroy(&histogram, allocator)
	}
	if stats, has_stats := result.stats.?; has_stats {
		if steps, has_steps := stats.steps.?; has_steps {
			capture_steps_destroy(&steps, allocator)
		}
	}
	result^ = {}
}
