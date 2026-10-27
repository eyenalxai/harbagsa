#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:game"
import "src:ui"

Scene_Settings_Patch :: struct {
	window_mode:  Maybe(string),
	display:      Maybe(int),
	resolution:   Maybe([2]i32),
	sprint_mode:  Maybe(string),
	type_weight:  Maybe(f32),
}

Scene_View_Patch :: struct {
	hud:   Maybe(bool),
	debug: Maybe(bool),
	hint:  Maybe(bool),
	perf:  Maybe(bool),
}

@(private)
parse_scene_settings :: proc(value: json.Value, allocator: mem.Allocator) -> (Scene_Settings_Patch, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scene 'settings' must be an object")
	}
	if key, unknown := json_unknown_key(
		object,
		{"window_mode", "display", "resolution", "sprint_mode", "type_weight"},
	); unknown {
		return {}, format_error("unknown settings key %q", key)
	}
	patch: Scene_Settings_Patch
	present := false
	if window_name, has := string_field(object, "window_mode"); has {
		if _, parsed := game.window_mode_parse(window_name); !parsed {
			return {}, format_error("%s", "settings 'window_mode' is not a known mode")
		}
		patch.window_mode = strings.clone(window_name, allocator)
		present = true
	}
	if display, has := integer_field(object, "display"); has {
		if display < 0 {
			return {}, format_error("%s", "settings 'display' must be non-negative")
		}
		patch.display = int(display)
		present = true
	}
	if resolution, has := vec2_int_field(object, "resolution"); has {
		if resolution[0] <= 0 || resolution[1] <= 0 {
			return {}, format_error("%s", "settings 'resolution' must be positive")
		}
		patch.resolution = resolution
		present = true
	}
	if name, has := string_field(object, "sprint_mode"); has {
		if _, parsed := game.input_mode_parse(name); !parsed {
			return {}, format_error("%s", "settings 'sprint_mode' is not a known mode")
		}
		patch.sprint_mode = strings.clone(name, allocator)
		present = true
	}
	if weight, has := number_field(object, "type_weight"); has {
		if weight < f64(ui.TYPE_WEIGHT_MIN) || weight > f64(ui.TYPE_WEIGHT_MAX) {
			return {}, format_error("%s", "settings 'type_weight' is out of range")
		}
		patch.type_weight = f32(weight)
		present = true
	}
	if !present {
		return {}, format_error("%s", "scene 'settings' needs at least one field")
	}
	return patch, ""
}

@(private)
parse_scene_view :: proc(value: json.Value) -> (Scene_View_Patch, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scene 'view' must be an object")
	}
	if key, unknown := json_unknown_key(object, {"hud", "debug", "hint", "perf"}); unknown {
		return {}, format_error("unknown view key %q", key)
	}
	view: Scene_View_Patch
	present := false
	if hud, has := json_boolean(json_get_required(object, "hud")); has {
		view.hud = hud
		present = true
	}
	if debug, has := json_boolean(json_get_required(object, "debug")); has {
		view.debug = debug
		present = true
	}
	if hint, has := json_boolean(json_get_required(object, "hint")); has {
		view.hint = hint
		present = true
	}
	if perf, has := json_boolean(json_get_required(object, "perf")); has {
		view.perf = perf
		present = true
	}
	if !present {
		return {}, format_error("%s", "scene 'view' needs at least one flag")
	}
	return view, ""
}
