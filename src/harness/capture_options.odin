#+vet explicit-allocators
package harness

import "core:encoding/json"

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
		if values[2] < 1 || values[3] < 1 {
			return format_error("%s", "a region needs a positive w and h")
		}
		command.region = capture_region_spec_pixels({values[0], values[1], values[2], values[3]})
		return ""
	}
	if !has_region {
		return ""
	}
	region, region_error := parse_region_value(region_value)
	if region_error != "" {
		return region_error
	}
	command.region = region
	return ""
}

parse_region_value :: proc(value: json.Value) -> (Capture_Region_Spec, string) {
	if array, array_ok := json_array(value); array_ok {
		if len(array) != 4 {
			return {}, format_error("%s", "a region array must be [x, y, w, h]")
		}
		values: [4]int
		for item, index in array {
			number, number_ok := json_integer(item)
			if !number_ok {
				return {}, format_error("%s", "a region array must hold integers")
			}
			values[index] = int(number)
		}
		if values[2] < 1 || values[3] < 1 {
			return {}, format_error("%s", "a region needs a positive w and h")
		}
		return capture_region_spec_pixels({values[0], values[1], values[2], values[3]}), ""
	}
	fields, fields_ok := json_object(value)
	if !fields_ok {
		return {}, format_error("%s", "a region must be an object with x, y, w, h")
	}
	if key, unknown := json_unknown_key(fields, {"x", "y", "w", "h", "unit"}); unknown {
		return {}, format_error("unknown region key %q", key)
	}
	unit_name, has_unit := string_field(fields, "unit")
	if has_unit && unit_name == "normalized" {
		x, x_ok := number_field(fields, "x")
		y, y_ok := number_field(fields, "y")
		w, w_ok := number_field(fields, "w")
		h, h_ok := number_field(fields, "h")
		if !x_ok || !y_ok || !w_ok || !h_ok ||
		   x < 0 || y < 0 || w <= 0 || h <= 0 ||
		   x + w > 1.000001 || y + h > 1.000001 {
			return {}, format_error(
				"%s",
				"a normalized region needs x, y in [0, 1], positive w, h, and x+w, y+h at most 1",
			)
		}
		return {
			unit = .Normalized,
			normalized = {f32(x), f32(y), f32(w), f32(h)},
		}, ""
	}
	if has_unit && unit_name != "pixels" {
		return {}, format_error("%s", "region 'unit' must be 'pixels' or 'normalized'")
	}
	x, x_ok := integer_field(fields, "x")
	y, y_ok := integer_field(fields, "y")
	w, w_ok := integer_field(fields, "w")
	h, h_ok := integer_field(fields, "h")
	if !x_ok || !y_ok || !w_ok || !h_ok || w < 1 || h < 1 {
		return {}, format_error("%s", "a region needs integer x, y and positive w, h")
	}
	return capture_region_spec_pixels({int(x), int(y), int(w), int(h)}), ""
}

@(private)
parse_capture_steps :: proc(value: json.Value) -> (Capture_Steps_Options, string) {
	fields, fields_ok := json_object(value)
	if !fields_ok {
		return {}, format_error("%s", "'steps' must be an object")
	}
	if key, unknown := json_unknown_key(fields, {"blur", "min", "max"}); unknown {
		return {}, format_error("unknown steps key %q", key)
	}
	options := capture_steps_default()
	if blur, has := json_get(fields, "blur"); has {
		blur_value, blur_ok := json_integer(blur)
		if !blur_ok || blur_value < 1 || blur_value > 31 || blur_value % 2 == 0 {
			return {}, format_error("%s", "'steps.blur' must be an odd integer in [1, 31]")
		}
		options.blur = int(blur_value)
	}
	if floor, has := json_get(fields, "min"); has {
		floor_value, floor_ok := json_number(floor)
		if !floor_ok || floor_value < 0 {
			return {}, format_error("%s", "'steps.min' must be a non-negative number")
		}
		options.min = f32(floor_value)
	}
	if cap, has := json_get(fields, "max"); has {
		cap_value, cap_ok := json_number(cap)
		if !cap_ok || cap_value <= f64(options.min) {
			return {}, format_error("%s", "'steps.max' must be above 'steps.min'")
		}
		options.max = f32(cap_value)
	}
	return options, ""
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
