#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"

import "src:renderer"

RENDERER_DEBUG_KEYS :: []string {
	"cmd",
	"clear",
	"taa",
	"jitter",
	"history_weight",
	"clamp",
	"depth_trust",
	"freeze_shadow_phase",
	"shadow_phase",
	"light_shadows",
	"synthetic_lights",
	"sky",
	"ao",
	"ao_radius",
	"ao_strength",
	"clip_height",
}

RENDERER_DEBUG_BLOCK_KEYS :: []string {
	"clear",
	"taa",
	"jitter",
	"history_weight",
	"clamp",
	"depth_trust",
	"freeze_shadow_phase",
	"shadow_phase",
	"light_shadows",
	"synthetic_lights",
	"sky",
	"ao",
	"ao_radius",
	"ao_strength",
	"clip_height",
}

@(private)
parse_renderer_debug :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, RENDERER_DEBUG_KEYS); unknown {
		return {}, format_error("unknown key %q", key)
	}
	fields, fields_error := renderer_debug_fields(object)
	if fields_error != "" {
		return {}, fields_error
	}
	return {kind = .Renderer_Debug, renderer_debug = fields}, ""
}

renderer_debug_fields :: proc(object: json.Object) -> (Renderer_Debug_Command, string) {
	command: Renderer_Debug_Command
	if field_error := json_bool(object, "clear", &command.clear); field_error != "" {
		return {}, field_error
	}
	if error := debug_bool(object, "taa", .TAA, &command.taa, &command.has_taa, &command.reset); error != "" {
		return {}, error
	}
	if error := debug_bool(object, "jitter", .Jitter, &command.jitter, &command.has_jitter, &command.reset); error != "" {
		return {}, error
	}
	if error := debug_number(
		object,
		"history_weight",
		.History_Weight,
		0,
		1,
		&command.history_weight,
		&command.has_history_weight,
		&command.reset,
	); error != "" {
		return {}, error
	}
	if error := debug_bool(object, "clamp", .Clamp, &command.clamp, &command.has_clamp, &command.reset); error != "" {
		return {}, error
	}
	if error := debug_bool(
		object,
		"depth_trust",
		.Depth_Trust,
		&command.depth_trust,
		&command.has_depth_trust,
		&command.reset,
	); error != "" {
		return {}, error
	}
	if error := debug_bool(
		object,
		"freeze_shadow_phase",
		.Freeze_Shadow_Phase,
		&command.freeze_shadow_phase,
		&command.has_freeze_shadow_phase,
		&command.reset,
	); error != "" {
		return {}, error
	}
	if error := debug_integer(
		object,
		"shadow_phase",
		.Shadow_Phase,
		0,
		63,
		&command.shadow_phase,
		&command.has_shadow_phase,
		&command.reset,
	); error != "" {
		return {}, error
	}
	if error := debug_bool(
		object,
		"light_shadows",
		.Light_Shadows,
		&command.light_shadows,
		&command.has_light_shadows,
		&command.reset,
	); error != "" {
		return {}, error
	}
	if error := debug_integer(
		object,
		"synthetic_lights",
		.Synthetic_Lights,
		0,
		max(int),
		&command.synthetic_lights,
		&command.has_synthetic_lights,
		&command.reset,
	); error != "" {
		return {}, error
	}
	if error := debug_bool(object, "sky", .Sky, &command.sky, &command.has_sky, &command.reset); error != "" {
		return {}, error
	}
	if error := debug_bool(object, "ao", .AO, &command.ao, &command.has_ao, &command.reset); error != "" {
		return {}, error
	}
	if error := debug_number(
		object,
		"ao_radius",
		.AO_Radius,
		0.01,
		50,
		&command.ao_radius,
		&command.has_ao_radius,
		&command.reset,
	); error != "" {
		return {}, error
	}
	if error := debug_number(
		object,
		"ao_strength",
		.AO_Strength,
		0,
		1,
		&command.ao_strength,
		&command.has_ao_strength,
		&command.reset,
	); error != "" {
		return {}, error
	}
	if error := debug_number(
		object,
		"clip_height",
		.Clip_Height,
		0,
		renderer.DEBUG_CLIP_HEIGHT_MAX,
		&command.clip_height,
		&command.has_clip_height,
		&command.reset,
	); error != "" {
		return {}, error
	}
	if command.clear && (command.has_taa ||
	   command.has_jitter ||
	   command.has_history_weight ||
	   command.has_clamp ||
	   command.has_depth_trust ||
	   command.has_freeze_shadow_phase ||
	   command.has_shadow_phase ||
	   command.has_light_shadows ||
	   command.has_synthetic_lights ||
	   command.has_sky ||
	   command.has_ao ||
	   command.has_ao_radius ||
	   command.has_ao_strength ||
	   command.has_clip_height ||
	   command.reset != {}) {
		return {}, "'clear' cannot be combined with overrides"
	}
	return command, ""
}

@(private)
debug_bool :: proc(
	object: json.Object,
	key: string,
	field: Renderer_Debug_Field,
	target: ^bool,
	has: ^bool,
	reset: ^Renderer_Debug_Resets,
) -> string {
	value, present := json_get(object, key)
	if !present {
		return ""
	}
	if json_is_null(value) {
		reset^ += {field}
		return ""
	}
	flag, ok := json_boolean(value)
	if !ok {
		return format_error("'%s' must be a boolean or null", key)
	}
	target^ = flag
	has^ = true
	return ""
}

@(private)
debug_number :: proc(
	object: json.Object,
	key: string,
	field: Renderer_Debug_Field,
	minimum, maximum: f64,
	target: ^f32,
	has: ^bool,
	reset: ^Renderer_Debug_Resets,
) -> string {
	value, present := json_get(object, key)
	if !present {
		return ""
	}
	if json_is_null(value) {
		reset^ += {field}
		return ""
	}
	number, ok := json_number(value)
	if !ok || number < minimum || number > maximum {
		return format_error("'%s' must be a number in [%g, %g] or null", key, minimum, maximum)
	}
	target^ = f32(number)
	has^ = true
	return ""
}

@(private)
debug_integer :: proc(
	object: json.Object,
	key: string,
	field: Renderer_Debug_Field,
	minimum, maximum: int,
	target: ^int,
	has: ^bool,
	reset: ^Renderer_Debug_Resets,
) -> string {
	value, present := json_get(object, key)
	if !present {
		return ""
	}
	if json_is_null(value) {
		reset^ += {field}
		return ""
	}
	number, ok := json_integer(value)
	if !ok || number < minimum || number > maximum {
		return format_error(
			"'%s' must be an integer in [%d, %d] or null",
			key,
			minimum,
			maximum,
		)
	}
	target^ = number
	has^ = true
	return ""
}
