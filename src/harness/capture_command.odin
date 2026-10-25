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
		{"cmd", "name", "frame", "alpha", "target", "format", "png", "region", "rect", "profile", "crop", "histogram", "steps"},
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
	if field_error := json_bool(object, "png", &command.capture.png); field_error != "" {
		return {}, field_error
	}
	if command.capture.format == .Png && command.capture.target != .Color {
		return {}, format_error("%s", "a png capture needs the color target")
	}
	if (command.capture.format == .Float || command.capture.format == .Raw) &&
	   command.capture.target == .Color {
		return {}, format_error("%s", "a float or raw capture needs an intermediate target")
	}
	if command.capture.png {
		if command.capture.target != .Color {
			return {}, format_error("%s", "a png sidecar needs the color target")
		}
		if command.capture.format != .Stats && command.capture.format != .Profile {
			return {}, format_error("%s", "'png' writes a sidecar for format 'stats' or 'profile'")
		}
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
	if value, has := json_get(object, "steps"); has {
		steps, steps_error := parse_capture_steps(value)
		if steps_error != "" {
			return {}, steps_error
		}
		command.capture.steps = steps
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
	_, has_steps := command.capture.steps.?
	if has_steps && command.capture.format != .Stats {
		return {}, format_error("%s", "a steps block needs format 'stats'")
	}
	_, has_profile := command.capture.profile.?
	if command.capture.format == .Profile && !has_profile {
		return {}, format_error("%s", "format 'profile' needs a 'profile' block")
	}
	if has_profile && command.capture.format != .Profile {
		return {}, format_error("%s", "a profile block needs format 'profile'")
	}
	if has_capture_name {
		command.capture.name = strings.clone(capture_name, allocator)
	}
	return command, ""
}
