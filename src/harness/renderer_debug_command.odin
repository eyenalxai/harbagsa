#+vet explicit-allocators
package harness

import "core:encoding/json"

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
			return {}, "'clear' must be a boolean"
		}
		command.clear = clear
	}
	if value, has := json_get(object, "taa"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'taa' must be a boolean"
		}
		command.taa = flag
		command.has_taa = true
	}
	if value, has := json_get(object, "jitter"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'jitter' must be a boolean"
		}
		command.jitter = flag
		command.has_jitter = true
	}
	if value, has := json_get(object, "history_weight"); has {
		weight, ok := json_number(value)
		if !ok || weight < 0 || weight > 1 {
			return {}, "'history_weight' must be a number in [0, 1]"
		}
		command.history_weight = f32(weight)
		command.has_history_weight = true
	}
	if value, has := json_get(object, "clamp"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'clamp' must be a boolean"
		}
		command.clamp = flag
		command.has_clamp = true
	}
	if value, has := json_get(object, "depth_trust"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'depth_trust' must be a boolean"
		}
		command.depth_trust = flag
		command.has_depth_trust = true
	}
	if value, has := json_get(object, "freeze_shadow_phase"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'freeze_shadow_phase' must be a boolean"
		}
		command.freeze_shadow_phase = flag
		command.has_freeze_shadow_phase = true
	}
	if value, has := json_get(object, "shadow_phase"); has {
		phase, ok := json_integer(value)
		if !ok || phase < 0 || phase >= 64 {
			return {}, "'shadow_phase' must be an integer in [0, 63]"
		}
		command.shadow_phase = int(phase)
		command.has_shadow_phase = true
	}
	if command.clear {
		if command.has_taa ||
		   command.has_jitter ||
		   command.has_history_weight ||
		   command.has_clamp ||
		   command.has_depth_trust ||
		   command.has_freeze_shadow_phase ||
		   command.has_shadow_phase {
			return {}, "'clear' cannot be combined with overrides"
		}
	}
	return command, ""
}
