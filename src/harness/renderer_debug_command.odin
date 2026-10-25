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
	if field_error := json_take_bool(object, "taa", &command.taa, &command.has_taa); field_error != "" {
		return {}, field_error
	}
	if field_error := json_take_bool(object, "jitter", &command.jitter, &command.has_jitter); field_error != "" {
		return {}, field_error
	}
	if value, has := json_get(object, "history_weight"); has {
		weight, ok := json_number(value)
		if !ok || weight < 0 || weight > 1 {
			return {}, format_error("%s", "'history_weight' must be a number in [0, 1]")
		}
		command.history_weight = f32(weight)
		command.has_history_weight = true
	}
	if field_error := json_take_bool(object, "clamp", &command.clamp, &command.has_clamp); field_error != "" {
		return {}, field_error
	}
	if field_error := json_take_bool(object, "depth_trust", &command.depth_trust, &command.has_depth_trust); field_error != "" {
		return {}, field_error
	}
	if field_error := json_take_bool(
		object,
		"freeze_shadow_phase",
		&command.freeze_shadow_phase,
		&command.has_freeze_shadow_phase,
	); field_error != "" {
		return {}, field_error
	}
	if value, has := json_get(object, "shadow_phase"); has {
		phase, ok := json_integer(value)
		if !ok || phase < 0 || phase >= 64 {
			return {}, format_error("%s", "'shadow_phase' must be an integer in [0, 63]")
		}
		command.shadow_phase = int(phase)
		command.has_shadow_phase = true
	}
	if field_error := json_take_bool(object, "light_shadows", &command.light_shadows, &command.has_light_shadows); field_error != "" {
		return {}, field_error
	}
	if value, has := json_get(object, "synthetic_lights"); has {
		count, ok := json_integer(value)
		if !ok || count < 0 || count > renderer.MAX_POINT_LIGHTS {
			return {}, "'synthetic_lights' must be an integer in [0, 8]"
		}
		command.synthetic_lights = int(count)
		command.has_synthetic_lights = true
	}
	if field_error := json_take_bool(object, "sky", &command.sky, &command.has_sky); field_error != "" {
		return {}, field_error
	}
	if field_error := json_take_bool(object, "ao", &command.ao, &command.has_ao); field_error != "" {
		return {}, field_error
	}
	if command.clear {
		if command.has_taa ||
		   command.has_jitter ||
		   command.has_history_weight ||
		   command.has_clamp ||
		   command.has_depth_trust ||
		   command.has_freeze_shadow_phase ||
		   command.has_shadow_phase ||
		   command.has_light_shadows ||
		   command.has_synthetic_lights ||
		   command.has_sky ||
		   command.has_ao {
			return {}, "'clear' cannot be combined with overrides"
		}
	}
	return command, ""
}
