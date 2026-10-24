#+vet explicit-allocators
package harness

import "core:encoding/json"

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
}

@(private)
parse_renderer_debug :: proc(object: json.Object) -> (Command, string) {
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
	if value, has := json_get(object, "clear"); has {
		clear, ok := json_boolean(value)
		if !ok {
			return {}, format_error("%s", "'clear' must be a boolean")
		}
		command.clear = clear
	}
	if value, has := json_get(object, "taa"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, format_error("%s", "'taa' must be a boolean")
		}
		command.taa = flag
		command.has_taa = true
	}
	if value, has := json_get(object, "jitter"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, format_error("%s", "'jitter' must be a boolean")
		}
		command.jitter = flag
		command.has_jitter = true
	}
	if value, has := json_get(object, "history_weight"); has {
		weight, ok := json_number(value)
		if !ok || weight < 0 || weight > 1 {
			return {}, format_error("%s", "'history_weight' must be a number in [0, 1]")
		}
		command.history_weight = f32(weight)
		command.has_history_weight = true
	}
	if value, has := json_get(object, "clamp"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, format_error("%s", "'clamp' must be a boolean")
		}
		command.clamp = flag
		command.has_clamp = true
	}
	if value, has := json_get(object, "depth_trust"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, format_error("%s", "'depth_trust' must be a boolean")
		}
		command.depth_trust = flag
		command.has_depth_trust = true
	}
	if value, has := json_get(object, "freeze_shadow_phase"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, format_error("%s", "'freeze_shadow_phase' must be a boolean")
		}
		command.freeze_shadow_phase = flag
		command.has_freeze_shadow_phase = true
	}
	if value, has := json_get(object, "shadow_phase"); has {
		phase, ok := json_integer(value)
		if !ok || phase < 0 || phase >= 64 {
			return {}, format_error("%s", "'shadow_phase' must be an integer in [0, 63]")
		}
		command.shadow_phase = int(phase)
		command.has_shadow_phase = true
	}
	if value, has := json_get(object, "light_shadows"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'light_shadows' must be a boolean"
		}
		command.light_shadows = flag
		command.has_light_shadows = true
	}
	if value, has := json_get(object, "synthetic_lights"); has {
		count, ok := json_integer(value)
		if !ok || count < 0 || count > renderer.MAX_POINT_LIGHTS {
			return {}, "'synthetic_lights' must be an integer in [0, 8]"
		}
		command.synthetic_lights = int(count)
		command.has_synthetic_lights = true
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
		   command.has_synthetic_lights {
			return {}, "'clear' cannot be combined with overrides"
		}
	}
	return command, ""
}
