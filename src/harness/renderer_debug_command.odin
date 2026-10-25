#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"

import "src:renderer"

Debug_Field_Kind :: enum {
	Bool,
	Integer,
	Number,
}

// One row per override: key, type, and range. The parser, the key list, and the
// reset patch read the table; the patch setters and the renderer conversion
// still name each field, because Odin has no typed field setter.
Debug_Field_Row :: struct {
	field:   Renderer_Debug_Field,
	name:    string,
	kind:    Debug_Field_Kind,
	minimum: f64,
	maximum: f64,
}

RENDERER_DEBUG_FIELD_ROWS := [?]Debug_Field_Row {
	{.TAA, "taa", .Bool, 0, 0},
	{.Jitter, "jitter", .Bool, 0, 0},
	{.History_Weight, "history_weight", .Number, 0, 1},
	{.Clamp, "clamp", .Bool, 0, 0},
	{.Depth_Trust, "depth_trust", .Bool, 0, 0},
	{.Freeze_Shadow_Phase, "freeze_shadow_phase", .Bool, 0, 0},
	{.Shadow_Phase, "shadow_phase", .Integer, 0, 63},
	{.Light_Shadows, "light_shadows", .Bool, 0, 0},
	{.Synthetic_Lights, "synthetic_lights", .Integer, 0, f64(max(int))},
	{.Sky, "sky", .Bool, 0, 0},
	{.GI, "gi", .Bool, 0, 0},
	{.AO, "ao", .Bool, 0, 0},
	{.AO_Radius, "ao_radius", .Number, 0.01, 50},
	{.AO_Strength, "ao_strength", .Number, 0, 1},
	{.Clip_Height, "clip_height", .Number, 0, renderer.DEBUG_CLIP_HEIGHT_MAX},
}

renderer_debug_keys :: proc(allocator: mem.Allocator, include_cmd: bool) -> []string {
	keys := make([dynamic]string, 0, len(RENDERER_DEBUG_FIELD_ROWS) + 2, allocator)
	if include_cmd {
		append(&keys, "cmd")
	}
	append(&keys, "clear")
	for row in RENDERER_DEBUG_FIELD_ROWS {
		append(&keys, row.name)
	}
	return keys[:]
}

renderer_debug_reset_patch :: proc(fields: Renderer_Debug_Resets) -> renderer.Renderer_Debug_Patch {
	defaults := renderer.renderer_debug_default()
	patch: renderer.Renderer_Debug_Patch
	for row in RENDERER_DEBUG_FIELD_ROWS {
		if row.field not_in fields {
			continue
		}
		switch row.field {
		case .TAA:
			patch.taa = defaults.taa
		case .Jitter:
			patch.jitter = defaults.jitter
		case .History_Weight:
			patch.history_weight = defaults.history_weight
		case .Clamp:
			patch.clamp = defaults.clamp
		case .Depth_Trust:
			patch.depth_trust = defaults.force_depth_trust
		case .Freeze_Shadow_Phase:
			patch.freeze_shadow_phase = defaults.freeze_shadow_phase
		case .Shadow_Phase:
			patch.shadow_phase = int(defaults.shadow_phase)
		case .Light_Shadows:
			patch.light_shadows = defaults.light_shadows
		case .Synthetic_Lights:
			patch.synthetic_lights = defaults.synthetic_lights
		case .Sky:
			patch.sky = defaults.sky
		case .GI:
			patch.gi = defaults.gi
		case .AO:
			patch.ao = defaults.ao
		case .AO_Radius:
			patch.ao_radius = defaults.ao_radius
		case .AO_Strength:
			patch.ao_strength = defaults.ao_strength
		case .Clip_Height:
			patch.clip_height = defaults.clip_height
		}
	}
	return patch
}

@(private)
parse_renderer_debug :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	allowed := renderer_debug_keys(context.temp_allocator, true)
	defer delete(allowed, context.temp_allocator)
	if key, unknown := json_unknown_key(object, allowed); unknown {
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
	for row in RENDERER_DEBUG_FIELD_ROWS {
		value, present := json_get(object, row.name)
		if !present {
			continue
		}
		if json_is_null(value) {
			command.reset += {row.field}
			continue
		}
		#partial switch row.kind {
		case .Bool:
			flag, ok := json_boolean(value)
			if !ok {
				return {}, format_error("'%s' must be a boolean or null", row.name)
			}
			debug_patch_set_bool(&command.patch, row.field, flag)
		case .Integer:
			number, ok := json_integer(value)
			if !ok || f64(number) < row.minimum || f64(number) > row.maximum {
				return {}, format_error(
					"'%s' must be an integer in [%d, %d] or null",
					row.name,
					int(row.minimum),
					int(row.maximum),
				)
			}
			debug_patch_set_integer(&command.patch, row.field, number)
		case .Number:
			number, ok := json_number(value)
			if !ok || number < row.minimum || number > row.maximum {
				return {}, format_error(
					"'%s' must be a number in [%g, %g] or null",
					row.name,
					row.minimum,
					row.maximum,
				)
			}
			debug_patch_set_number(&command.patch, row.field, f32(number))
		}
	}
	if command.clear && (command.patch != {} || command.reset != {}) {
		return {}, "'clear' cannot be combined with overrides"
	}
	return command, ""
}

@(private)
debug_patch_set_bool :: proc(
	patch: ^renderer.Renderer_Debug_Patch,
	field: Renderer_Debug_Field,
	value: bool,
) {
	#partial switch field {
	case .TAA:
		patch.taa = value
	case .Jitter:
		patch.jitter = value
	case .Clamp:
		patch.clamp = value
	case .Depth_Trust:
		patch.depth_trust = value
	case .Freeze_Shadow_Phase:
		patch.freeze_shadow_phase = value
	case .Light_Shadows:
		patch.light_shadows = value
	case .Sky:
		patch.sky = value
	case .GI:
		patch.gi = value
	case .AO:
		patch.ao = value
	}
}

@(private)
debug_patch_set_integer :: proc(
	patch: ^renderer.Renderer_Debug_Patch,
	field: Renderer_Debug_Field,
	value: int,
) {
	#partial switch field {
	case .Shadow_Phase:
		patch.shadow_phase = value
	case .Synthetic_Lights:
		patch.synthetic_lights = value
	}
}

@(private)
debug_patch_set_number :: proc(
	patch: ^renderer.Renderer_Debug_Patch,
	field: Renderer_Debug_Field,
	value: f32,
) {
	#partial switch field {
	case .History_Weight:
		patch.history_weight = value
	case .AO_Radius:
		patch.ao_radius = value
	case .AO_Strength:
		patch.ao_strength = value
	case .Clip_Height:
		patch.clip_height = value
	}
}
