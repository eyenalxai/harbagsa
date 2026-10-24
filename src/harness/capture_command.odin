#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:renderer"

@(private)
parse_capture :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(
		object,
		{"cmd", "name", "frame", "alpha", "target", "format", "region", "rect", "profile", "crop", "histogram"},
	); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Capture}
	capture_name: string
	has_capture_name := false
	if value, has := json_get(object, "name"); has {
		name, ok := json_string(value)
		if !ok || !valid_capture_name(name) {
			return {}, format_error("%s", "'name' must use only letters, digits, '-' and '_'")
		}
		capture_name = name
		has_capture_name = true
	}
	if value, has := json_get(object, "frame"); has {
		frame, ok := json_integer(value)
		if !ok || frame < 0 {
			return {}, format_error("%s", "'frame' must be a non-negative integer")
		}
		command.capture.frame = frame
		command.capture.has_frame = true
	}
	if value, has := json_get(object, "alpha"); has {
		alpha, ok := json_number(value)
		if !ok || alpha < 0 || alpha > 1 {
			return {}, format_error("%s", "'alpha' must be a number in [0, 1]")
		}
		command.capture.alpha = f32(alpha)
		command.capture.has_alpha = true
	}
	if value, has := json_get(object, "target"); has {
		name, ok := json_string(value)
		target, target_ok := renderer.capture_target_parse(name)
		if !ok || !target_ok {
			return {}, format_error("%s", "'target' must be color, velocity, history, depth, or scene_color")
		}
		command.capture.target = target
	}
	if value, has := json_get(object, "format"); has {
		name, ok := json_string(value)
		format, format_ok := capture_format_parse(name)
		if !ok || !format_ok {
			return {}, format_error("%s", "'format' must be png, float, raw, stats, or profile")
		}
		command.capture.format = format
	} else {
		command.capture.format = command.capture.target == .Color ? .Png : .Stats
	}
	if command.capture.format == .Png && command.capture.target != .Color {
		return {}, format_error("%s", "a png capture needs the color target")
	}
	if (command.capture.format == .Float || command.capture.format == .Raw) &&
	   command.capture.target == .Color {
		return {}, format_error("%s", "a float or raw capture needs an intermediate target")
	}
	if region_error := parse_capture_region(object, &command.capture); region_error != "" {
		return {}, region_error
	}
	if profile_error := parse_capture_profile(object, &command.capture); profile_error != "" {
		return {}, profile_error
	}
	if crop_error := parse_capture_crop(object, &command.capture); crop_error != "" {
		return {}, crop_error
	}
	if value, has := json_get(object, "histogram"); has {
		bins, ok := json_integer(value)
		if !ok || bins < 1 || bins > 256 {
			return {}, format_error("%s", "'histogram' must be a bin count in [1, 256]")
		}
		command.capture.histogram = bins
	}
	// A region and a histogram read the statistics path, a crop writes a PNG,
	// and a profile decodes the color image.
	_, has_region := command.capture.region.?
	if has_region && command.capture.format != .Stats {
		return {}, format_error("%s", "'region' needs format 'stats'")
	}
	_, has_histogram := command.capture.histogram.?
	if has_histogram && command.capture.format != .Stats {
		return {}, format_error("%s", "'histogram' needs format 'stats'")
	}
	_, has_crop := command.capture.crop.?
	if has_crop && command.capture.format != .Png {
		return {}, format_error("%s", "'crop' needs format 'png'")
	}
	_, has_profile := command.capture.profile.?
	if command.capture.format == .Profile && !has_profile {
		return {}, format_error("%s", "format 'profile' needs a 'profile' block")
	}
	if has_profile && command.capture.target != .Color {
		return {}, format_error("%s", "a profile reads the color target")
	}
	if has_capture_name {
		command.capture.name = strings.clone(capture_name, allocator)
	}
	return command, ""
}

@(private)
parse_capture_region :: proc(object: json.Object, command: ^Capture_Command) -> string {
	region_value, has_region := json_get(object, "region")
	rect_value, has_rect := json_get(object, "rect")
	if has_region && has_rect {
		return format_error("%s", "capture takes 'region' or 'rect', not both")
	}
	if has_rect {
		array, array_ok := json_array(rect_value)
		if !array_ok || len(array) != 4 {
			return format_error("%s", "'rect' must be [x, y, w, h]")
		}
		values: [4]int
		for item, index in array {
			value, ok := json_integer(item)
			if !ok {
				return format_error("%s", "'rect' must hold integers")
			}
			values[index] = int(value)
		}
		command.region = Capture_Region{values[0], values[1], values[2], values[3]}
		return ""
	}
	if !has_region {
		return ""
	}
	fields, fields_ok := json_object(region_value)
	if !fields_ok {
		return format_error("%s", "'region' must be an object with x, y, w, h")
	}
	if key, unknown := json_unknown_key(fields, {"x", "y", "w", "h"}); unknown {
		return format_error("unknown region key %q", key)
	}
	x, x_ok := integer_field(fields, "x")
	y, y_ok := integer_field(fields, "y")
	w, w_ok := integer_field(fields, "w")
	h, h_ok := integer_field(fields, "h")
	if !x_ok || !y_ok || !w_ok || !h_ok || w < 1 || h < 1 {
		return format_error("%s", "'region' needs integer x, y and positive w, h")
	}
	command.region = Capture_Region{int(x), int(y), int(w), int(h)}
	return ""
}

@(private)
parse_capture_profile :: proc(object: json.Object, command: ^Capture_Command) -> string {
	profile_value, has_profile := json_get(object, "profile")
	if !has_profile {
		return ""
	}
	fields, fields_ok := json_object(profile_value)
	if !fields_ok {
		return format_error("%s", "'profile' must be an object")
	}
	if key, unknown := json_unknown_key(
		fields,
		{"axis", "at", "from", "to", "channel", "mean", "low", "high"},
	); unknown {
		return format_error("unknown profile key %q", key)
	}
	profile := Capture_Profile{}
	axis_name, axis_ok := string_field(fields, "axis")
	if !axis_ok {
		return format_error("%s", "'profile' needs 'axis' ('x' or 'y')")
	}
	axis, parsed_axis := profile_axis_parse(axis_name)
	if !parsed_axis {
		return format_error("%s", "'profile.axis' must be 'x' or 'y'")
	}
	profile.axis = axis
	if channel_name, channel_ok := string_field(fields, "channel"); channel_ok {
		channel, parsed_channel := profile_channel_parse(channel_name)
		if !parsed_channel {
			return format_error("%s", "'profile.channel' must be luma, x, y, or z")
		}
		profile.channel = channel
	}
	if mean_value, has_mean := json_get(fields, "mean"); has_mean {
		mean, ok := json_boolean(mean_value)
		if !ok {
			return format_error("%s", "'profile.mean' must be a boolean")
		}
		profile.mean = mean
	}
	at, has_at := integer_field(fields, "at")
	if !profile.mean && !has_at {
		return format_error("%s", "'profile' needs 'at' unless 'mean' is set")
	}
	profile.at = int(at)
	from, has_from := integer_field(fields, "from")
	to, has_to := integer_field(fields, "to")
	if !has_from || !has_to {
		return format_error("%s", "'profile' needs 'from' and 'to'")
	}
	if from < 0 || to < from {
		return format_error("%s", "'profile.from' must be a non-negative index no greater than 'to'")
	}
	profile.from = int(from)
	profile.to = int(to)
	if low_value, has_low := json_get(fields, "low"); has_low {
		low, ok := json_number(low_value)
		if !ok || low < 0 || low > 1 {
			return format_error("%s", "'profile.low' must be a fraction in [0, 1]")
		}
		profile.low = f32(low)
		profile.has_low = true
	}
	if high_value, has_high := json_get(fields, "high"); has_high {
		high, ok := json_number(high_value)
		if !ok || high < 0 || high > 1 {
			return format_error("%s", "'profile.high' must be a fraction in [0, 1]")
		}
		profile.high = f32(high)
		profile.has_high = true
	}
	if profile.has_low && profile.has_high && profile.low >= profile.high {
		return format_error("%s", "'profile.low' must be below 'profile.high'")
	}
	command.profile = profile
	return ""
}

@(private)
parse_capture_crop :: proc(object: json.Object, command: ^Capture_Command) -> string {
	value, has := json_get(object, "crop")
	if !has {
		return ""
	}
	fields, fields_ok := json_object(value)
	if !fields_ok {
		return format_error("%s", "'crop' must be an object with x, y, w, h, scale")
	}
	if key, unknown := json_unknown_key(fields, {"x", "y", "w", "h", "scale"}); unknown {
		return format_error("unknown crop key %q", key)
	}
	x, x_ok := integer_field(fields, "x")
	y, y_ok := integer_field(fields, "y")
	w, w_ok := integer_field(fields, "w")
	h, h_ok := integer_field(fields, "h")
	if !x_ok || !y_ok || !w_ok || !h_ok || w < 1 || h < 1 {
		return format_error("%s", "'crop' needs integer x, y and positive w, h")
	}
	scale := 1
	if scale_value, has_scale := json_get(fields, "scale"); has_scale {
		parsed, ok := json_integer(scale_value)
		if !ok || parsed < 1 || parsed > 8 {
			return format_error("%s", "'crop.scale' must be an integer in [1, 8]")
		}
		scale = int(parsed)
	}
	command.crop = Capture_Crop{int(x), int(y), int(w), int(h), scale}
	return ""
}
