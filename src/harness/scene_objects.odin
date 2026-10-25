#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:display"
import "src:frame"
import "src:game"

@(private)
parse_scene_objects :: proc(value: json.Value, allocator: mem.Allocator) -> ([]frame.Scene_Object, string) {
	array, array_ok := json_array(value)
	if !array_ok {
		return nil, format_error("%s", "scene 'objects' must be an array")
	}
	objects := make([]frame.Scene_Object, len(array), allocator)
	ok := false
	defer if !ok {
		for object in objects {
			delete(object.prefab, allocator)
			delete(object.body, allocator)
			delete(object.light.color, allocator)
		}
		delete(objects, allocator)
	}
	for item, index in array {
		object, object_ok := json_object(item)
		if !object_ok {
			return nil, format_error("scene object %d must be an object", index)
		}
		if key, unknown := json_unknown_key(
			object,
			{"id", "prefab", "body", "position", "rotation", "color", "light"},
		); unknown {
			return nil, format_error("unknown scene object key %q", key)
		}
		id, id_ok := json_integer(json_get_required(object, "id"))
		prefab_name, prefab_ok := string_field(object, "prefab")
		prefab, prefab_parsed := game.prefab_parse(prefab_name)
		body_name, body_ok := string_field(object, "body")
		_, body_parsed := game.body_mode_parse(body_name)
		position, position_ok := vec3_field(object, "position")
		rotation, rotation_ok := vec4_float_field(object, "rotation")
		if !id_ok || id < 0 || !prefab_ok || !prefab_parsed || !body_ok || !body_parsed ||
		   !position_ok || !rotation_ok {
			return nil, format_error(
				"scene object %d needs id, prefab, body, position, and rotation",
				index,
			)
		}
		color := game.prefab_color(prefab)
		if color_value, has := json_get(object, "color"); has {
			parsed_color, color_ok := vec4_float_value(color_value)
			if !color_ok {
				return nil, format_error("scene object %d color must hold four numbers", index)
			}
			color = parsed_color
		}
		light := game.prefab(prefab).light
		if light_value, has := json_get(object, "light"); has {
			parsed_light, light_error := parse_scene_light(light_value, allocator)
			if light_error != "" {
				return nil, light_error
			}
			light = parsed_light
		}
		objects[index] = {
			id = u32(id),
			prefab = strings.clone(prefab_name, allocator),
			body = strings.clone(body_name, allocator),
			position = position,
			rotation = rotation,
			color = color,
			light = {
				active = light.active,
				color = strings.clone(game.light_color_name(light.color), allocator),
				intensity = light.intensity,
				range = light.range,
				emissive = light.emissive,
			},
		}
	}
	ok = true
	return objects, ""
}

@(private)
parse_scene_light :: proc(value: json.Value, allocator: mem.Allocator) -> (game.Light_Settings, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scene light must be an object")
	}
	if key, unknown := json_unknown_key(object, {"active", "color", "intensity", "range", "emissive"}); unknown {
		return {}, format_error("unknown scene light key %q", key)
	}
	active_value, active_ok := json_get(object, "active")
	active, active_parsed := json_boolean(active_value)
	color_name, color_ok := string_field(object, "color")
	color, color_parsed := game.light_color_parse(color_name)
	intensity, intensity_ok := number_field(object, "intensity")
	range, range_ok := number_field(object, "range")
	emissive, emissive_ok := number_field(object, "emissive")
	if !active_ok || !active_parsed || !color_ok || !color_parsed ||
	   !intensity_ok || !range_ok || !emissive_ok {
		return {}, format_error("%s", "scene light needs active, color, intensity, range, and emissive")
	}
	if active {
		if intensity < game.LIGHT_INTENSITY_MIN || intensity > game.LIGHT_INTENSITY_MAX ||
		   range < game.LIGHT_RANGE_MIN || range > game.LIGHT_RANGE_MAX ||
		   emissive < 0 {
			return {}, format_error("%s", "an active scene light needs intensity in [0.2, 4.0], range in [2, 20], and emissive >= 0")
		}
	} else if intensity < 0 || range < 0 || emissive < 0 {
		return {}, format_error("%s", "an inactive scene light needs non-negative values")
	}
	_ = allocator
	return {
		active = active,
		color = color,
		intensity = f32(intensity),
		range = f32(range),
		emissive = f32(emissive),
	}, ""
}

@(private)
vec4_float_field :: proc(object: json.Object, key: string) -> (value: [4]f32, ok: bool) {
	entry, has := json_get(object, key)
	if !has {
		return {}, false
	}
	return vec4_float_value(entry)
}

@(private)
vec4_float_value :: proc(value: json.Value) -> ([4]f32, bool) {
	array, array_ok := json_array(value)
	if !array_ok || len(array) != 4 {
		return {}, false
	}
	result: [4]f32
	for item, index in array {
		number, number_ok := json_number(item)
		if !number_ok {
			return {}, false
		}
		result[index] = f32(number)
	}
	return result, true
}

@(private)
parse_scene_displays :: proc(value: json.Value, allocator: mem.Allocator) -> ([]frame.Scene_Display, string) {
	array, array_ok := json_array(value)
	if !array_ok {
		return nil, format_error("%s", "scene 'displays' must be an array")
	}
	if len(array) > display.MAX_DISPLAYS {
		return nil, format_error("scene holds at most %d displays", display.MAX_DISPLAYS)
	}
	displays := make([]frame.Scene_Display, len(array), allocator)
	ok := false
	defer if !ok {
		for display_entry in displays {
			delete(display_entry.name, allocator)
			delete(display_entry.modes, allocator)
		}
		delete(displays, allocator)
	}
	for item, index in array {
		object, object_ok := json_object(item)
		if !object_ok {
			return nil, format_error("display %d must be an object", index)
		}
		if key, unknown := json_unknown_key(object, {"name", "desktop", "modes"}); unknown {
			return nil, format_error("unknown display key %q", key)
		}
		name, name_ok := string_field(object, "name")
		desktop, desktop_ok := vec2_int_field(object, "desktop")
		modes_array, modes_ok := json_array(json_get_required(object, "modes"))
		if !name_ok || name == "" || !desktop_ok || !modes_ok || len(modes_array) > display.MAX_MODES {
			return nil, format_error("display %d needs a name, desktop, and at most %d modes", index, display.MAX_MODES)
		}
		modes := make([][2]i32, len(modes_array), allocator)
		for mode_item, mode_index in modes_array {
			mode, mode_ok := vec2_int_value(mode_item)
			if !mode_ok || mode[0] <= 0 || mode[1] <= 0 {
				return nil, format_error("display %d mode %d needs positive width and height", index, mode_index)
			}
			modes[mode_index] = mode
		}
		displays[index] = {
			name = strings.clone(name, allocator),
			desktop = desktop,
			modes = modes,
		}
	}
	ok = true
	return displays, ""
}

vec2_int_value :: proc(value: json.Value) -> ([2]i32, bool) {
	array, array_ok := json_array(value)
	if !array_ok || len(array) != 2 {
		return {}, false
	}
	result: [2]i32
	for item, index in array {
		number, number_ok := json_integer(item)
		if !number_ok {
			return {}, false
		}
		result[index] = i32(number)
	}
	return result, true
}
