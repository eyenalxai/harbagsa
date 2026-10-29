#+vet explicit-allocators
package harness

import "core:encoding/json"

import "src:game"

// The light group. A field applies to the next lamp placement while the palette
// or the placement tool owns the editor, and to the selected lamp otherwise.
Editor_Light :: struct {
	kind:          game.Lamp_Kind,
	has_kind:      bool,
	color:         game.Light_Color,
	has_color:     bool,
	intensity:     f32,
	has_intensity: bool,
	range:         f32,
	has_range:     bool,
}

@(private)
parse_editor_light :: proc(object: json.Object) -> (Editor_Light, string) {
	editor: Editor_Light
	if value, has := json_get(object, "light_kind"); has {
		name, ok := json_string(value)
		kind, parsed := game.lamp_kind_parse(name)
		if !ok || !parsed {
			return {}, format_error("%s", "'light_kind' must be 'static' or 'dynamic'")
		}
		editor.kind = kind
		editor.has_kind = true
	}
	if value, has := json_get(object, "light_color"); has {
		name, ok := json_string(value)
		if !ok {
			return {}, format_error("%s", "'light_color' must be a string")
		}
		color, parsed := game.light_color_parse(name)
		if !parsed {
			return {}, format_error(
				"unknown light colour %q; use warm, cool, red, green, or blue",
				name,
			)
		}
		editor.color = color
		editor.has_color = true
	}
	if value, has := json_get(object, "light_intensity"); has {
		intensity, ok := json_number(value)
		if !ok ||
		   intensity < game.LIGHT_INTENSITY_MIN ||
		   intensity > game.LIGHT_INTENSITY_MAX {
			return {}, format_error(
				"'light_intensity' must be a number in [%.1f, %.1f]",
				game.LIGHT_INTENSITY_MIN,
				game.LIGHT_INTENSITY_MAX,
			)
		}
		editor.intensity = f32(intensity)
		editor.has_intensity = true
	}
	if value, has := json_get(object, "light_range"); has {
		range, ok := json_number(value)
		if !ok || range < game.LIGHT_RANGE_MIN || range > game.LIGHT_RANGE_MAX {
			return {}, format_error(
				"'light_range' must be a number in [%.0f, %.0f]",
				game.LIGHT_RANGE_MIN,
				game.LIGHT_RANGE_MAX,
			)
		}
		editor.range = f32(range)
		editor.has_range = true
	}
	return editor, ""
}
