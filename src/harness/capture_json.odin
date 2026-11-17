#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strings"

import "src:renderer"

// One writer for the capture command document. The parser above accepts this
// shape, so a recorded capture keeps every option it was given.
capture_command_json :: proc(capture: Capture_Command, allocator: mem.Allocator) -> string {
	builder := strings.builder_make(allocator)
	fmt.sbprint(&builder, `{"cmd": "capture"`)
	has_previous := true
	capture_json_fields(&builder, capture, true, &has_previous)
	fmt.sbprint(&builder, `}`)
	return strings.to_string(builder)
}

json_write_separator :: proc(builder: ^strings.Builder, has_previous: ^bool) {
	if has_previous^ {
		fmt.sbprint(builder, `, `)
	}
	has_previous^ = true
}

json_write_string :: proc(builder: ^strings.Builder, value: string) {
	data, encode_error := json.marshal(value, {}, context.temp_allocator)
	if encode_error != nil {
		strings.write_string(builder, `""`)
		return
	}
	strings.write_bytes(builder, data)
}

capture_json_fields :: proc(
	builder: ^strings.Builder,
	capture: Capture_Command,
	with_timing: bool,
	has_previous: ^bool,
) {
	if capture.name != "" {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"name": `)
		json_write_string(builder, capture.name)
	}
	if capture.note != "" {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"note": `)
		json_write_string(builder, capture.note)
	}
	if with_timing {
		if capture.has_frame {
			json_write_separator(builder, has_previous)
			fmt.sbprintf(builder, `"frame": %d`, capture.frame)
		}
		if capture.has_alpha {
			json_write_separator(builder, has_previous)
			fmt.sbprintf(builder, `"alpha": %g`, capture.alpha)
		}
	}
	if capture.target != .Color {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"target": `)
		json_write_string(builder, renderer.capture_target_name(capture.target))
	}
	if capture.format != .Png {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"format": `)
		json_write_string(builder, capture_format_name(capture.format))
	}
	if capture.png {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"png": true`)
	}
	if region, has := capture.region.?; has {
		json_write_separator(builder, has_previous)
		if region.unit == .Normalized {
			fmt.sbprintf(
				builder,
				`"region": {{"unit": "normalized", "x": %g, "y": %g, "w": %g, "h": %g}}`,
				region.normalized[0],
				region.normalized[1],
				region.normalized[2],
				region.normalized[3],
			)
		} else {
			fmt.sbprintf(
				builder,
				`"region": {{"x": %d, "y": %d, "w": %d, "h": %d}}`,
				region.pixels.x,
				region.pixels.y,
				region.pixels.w,
				region.pixels.h,
			)
		}
	}
	if profile, has := capture.profile.?; has {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"profile": {"axis": `)
		json_write_string(builder, profile_axis_name(profile.axis))
		fmt.sbprint(builder, `, "channel": `)
		json_write_string(builder, profile_channel_name(profile.channel))
		fmt.sbprintf(
			builder,
			`, "at": %d, "from": %d, "to": %d`,
			profile.at,
			profile.from,
			profile.to,
		)
		if profile.mean {
			fmt.sbprint(builder, `, "mean": true`)
		}
		if profile.has_low {
			fmt.sbprintf(builder, `, "low": %g`, profile.low)
		}
		if profile.has_high {
			fmt.sbprintf(builder, `, "high": %g`, profile.high)
		}
		fmt.sbprint(builder, `}`)
	}
	if crop, has := capture.crop.?; has {
		json_write_separator(builder, has_previous)
		fmt.sbprintf(
			builder,
			`"crop": {{"x": %d, "y": %d, "w": %d, "h": %d, "scale": %d}}`,
			crop.x,
			crop.y,
			crop.w,
			crop.h,
			crop.scale,
		)
	}
	if bins, has := capture.histogram.?; has {
		json_write_separator(builder, has_previous)
		fmt.sbprintf(builder, `"histogram": %d`, bins)
	}
	if steps, has := capture.steps.?; has {
		json_write_separator(builder, has_previous)
		fmt.sbprintf(
			builder,
			`"steps": {{"blur": %d, "min": %g, "max": %g}}`,
			steps.blur,
			steps.min,
			steps.max,
		)
	}
	if key, has := capture.color_key.?; has {
		json_write_separator(builder, has_previous)
		fmt.sbprintf(
			builder,
			`"color_key": {{"r": %d, "g": %d, "b": %d, "tolerance": %g}}`,
			key.r,
			key.g,
			key.b,
			key.tolerance,
		)
	}
	if coverage, has := capture.coverage.?; has {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"coverage": {`)
		first := true
		if value, has_black := coverage.black.?; has_black {
			fmt.sbprintf(builder, `"black": %g`, value)
			first = false
		}
		if value, has_lit := coverage.lit.?; has_lit {
			if !first {
				fmt.sbprint(builder, `, `)
			}
			fmt.sbprintf(builder, `"lit": %g`, value)
		}
		fmt.sbprint(builder, `}`)
	}
	if require, has := capture.require.?; has {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"require": {`)
		first := true
		if value, has_min := require.lit_fraction_min.?; has_min {
			fmt.sbprintf(builder, `"lit_fraction_min": %g`, value)
			first = false
		}
		if value, has_max := require.zero_fraction_max.?; has_max {
			if !first {
				fmt.sbprint(builder, `, `)
			}
			fmt.sbprintf(builder, `"zero_fraction_max": %g`, value)
		}
		fmt.sbprint(builder, `}`)
	}
	if len(capture.expect_state) > 0 {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"expect_state": {`)
		for expect, index in capture.expect_state {
			if index > 0 {
				fmt.sbprint(builder, `, `)
			}
			json_write_string(builder, expect.path)
			fmt.sbprint(builder, `: `)
			switch expect.value.kind {
			case .Number:
				fmt.sbprintf(builder, `%g`, expect.value.number)
			case .Bool:
				fmt.sbprint(builder, expect.value.boolean ? `true` : `false`)
			case .String:
				json_write_string(builder, expect.value.text)
			}
		}
		fmt.sbprint(builder, `}`)
	}
	if len(capture.views) > 0 {
		json_write_separator(builder, has_previous)
		fmt.sbprint(builder, `"views": [`)
		for view, index in capture.views {
			if index > 0 {
				fmt.sbprint(builder, `, `)
			}
			json_write_string(builder, renderer.capture_view_name(view))
		}
		fmt.sbprint(builder, `]`)
	}
}
