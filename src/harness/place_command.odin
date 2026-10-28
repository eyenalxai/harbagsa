#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:math"
import "core:mem"

import "src:game"

PLACE_KEYS := [?]string{"cmd", "prefab", "position", "yaw_deg", "body", "light", "name"}
PLACE_LIGHT_KEYS := [?]string{"kind", "color", "intensity", "range"}

Place_Light :: struct {
	kind:          game.Lamp_Kind,
	has_kind:      bool,
	color:         game.Light_Color,
	has_color:     bool,
	intensity:     f32,
	has_intensity: bool,
	range:         f32,
	has_range:     bool,
}

Place_Command :: struct {
	name:     Object_Name,
	prefab:   game.Prefab_Id,
	position: [3]f32,
	yaw_deg:  f32,
	body:     game.Body_Mode,
	light:    Place_Light,
}

Remove_Command :: struct {
	id:   game.Object_Id,
	name: Object_Name,
	has_id: bool,
	has_name: bool,
}

@(private)
parse_place :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, PLACE_KEYS[:]); unknown {
		return {}, format_error("unknown key %q", key)
	}
	name, name_ok := string_field(object, "prefab")
	prefab, prefab_ok := game.prefab_parse(name)
	position, position_ok := vec3_field(object, "position")
	if !name_ok || !prefab_ok {
		return {}, format_error("%s", "place needs a known string 'prefab'")
	}
	if !position_ok {
		return {}, format_error("%s", "place needs a 'position' of three numbers")
	}
	_ = allocator
	command := Command {
		kind = .Place,
		place = {
			prefab = prefab,
			position = position,
			body = game.prefab(prefab).body_mode,
		},
	}
	if value, has := json_get(object, "yaw_deg"); has {
		yaw, yaw_ok := json_number(value)
		if !yaw_ok {
			return {}, format_error("%s", "'yaw_deg' must be a number")
		}
		command.place.yaw_deg = f32(yaw)
	}
	if value, has := json_get(object, "body"); has {
		body, body_error := parse_body_mode(value, "body")
		if body_error != "" {
			return {}, body_error
		}
		command.place.body = body
	}
	if value, has := json_get(object, "light"); has {
		light, light_error := parse_place_light(value, prefab)
		if light_error != "" {
			return {}, light_error
		}
		command.place.light = light
	}
	if value, has := json_get(object, "name"); has {
		text, text_ok := json_string(value)
		parsed, parsed_ok := object_name_from_text(text)
		if !text_ok || !parsed_ok {
			return {}, format_error(
				"%s",
				"'name' must use at most 31 letters, digits, '-' or '_' and not be all digits",
			)
		}
		command.place.name = parsed
	}
	return command, ""
}

@(private)
parse_place_light :: proc(value: json.Value, prefab: game.Prefab_Id) -> (Place_Light, string) {
	if !game.prefab_has_light(prefab) {
		return {}, format_error("prefab %q has no light", game.prefab_name(prefab))
	}
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "place 'light' must be an object")
	}
	if key, unknown := json_unknown_key(object, PLACE_LIGHT_KEYS[:]); unknown {
		return {}, format_error("unknown place light key %q", key)
	}
	light: Place_Light
	if kind_value, has := json_get(object, "kind"); has {
		name, ok := json_string(kind_value)
		kind, parsed := game.lamp_kind_parse(name)
		if !ok || !parsed {
			return {}, format_error("%s", "place light 'kind' must be 'dynamic' or 'static'")
		}
		light.kind = kind
		light.has_kind = true
	}
	if color_value, has := json_get(object, "color"); has {
		name, ok := json_string(color_value)
		if !ok {
			return {}, format_error("%s", "place light 'color' must be a string")
		}
		color, parsed := game.light_color_parse(name)
		if !parsed {
			return {}, format_error(
				"unknown light colour %q; use warm, cool, red, green, or blue",
				name,
			)
		}
		light.color = color
		light.has_color = true
	}
	if intensity_value, has := json_get(object, "intensity"); has {
		intensity, ok := json_number(intensity_value)
		if !ok ||
		   intensity < game.LIGHT_INTENSITY_MIN ||
		   intensity > game.LIGHT_INTENSITY_MAX {
			return {}, format_error(
				"place light 'intensity' must be a number in [%.1f, %.1f]",
				game.LIGHT_INTENSITY_MIN,
				game.LIGHT_INTENSITY_MAX,
			)
		}
		light.intensity = f32(intensity)
		light.has_intensity = true
	}
	if range_value, has := json_get(object, "range"); has {
		range, ok := json_number(range_value)
		if !ok || range < game.LIGHT_RANGE_MIN || range > game.LIGHT_RANGE_MAX {
			return {}, format_error(
				"place light 'range' must be a number in [%.0f, %.0f]",
				game.LIGHT_RANGE_MIN,
				game.LIGHT_RANGE_MAX,
			)
		}
		light.range = f32(range)
		light.has_range = true
	}
	return light, ""
}

@(private)
parse_remove :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	_ = allocator
	if key, unknown := json_unknown_key(object, {"cmd", "id", "name"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	id_value, has_id := json_get(object, "id")
	name_value, has_name := json_get(object, "name")
	if has_id == has_name {
		return {}, format_error("%s", "remove needs 'id' or 'name'")
	}
	command := Command{kind = .Remove}
	if has_id {
		id, ok := json_integer(id_value)
		if !ok || id <= 0 {
			return {}, format_error("%s", "remove needs a positive integer 'id'")
		}
		command.remove.id = game.Object_Id(id)
		command.remove.has_id = true
	} else {
		text, text_ok := json_string(name_value)
		name, name_ok := object_name_from_text(text)
		if !text_ok || !name_ok || text == "" {
			return {}, format_error("%s", "remove 'name' must be a placed object name")
		}
		command.remove.name = name
		command.remove.has_name = true
	}
	return command, ""
}

session_place :: proc(session: ^Session, command: Place_Command, reply: ^Reply) -> string {
	place_name := command.name
	name := object_name_text(&place_name)
	if name != "" && game.object_name_taken(&session.sim, name) {
		return format_error("object name %q is taken", name)
	}
	light := game.prefab_light(command.prefab)
	if command.light.has_kind {
		light.kind = command.light.kind
	}
	if command.light.has_color {
		light.color = command.light.color
	}
	if command.light.has_intensity {
		light.intensity = command.light.intensity
		light.emissive = game.light_emissive(light.intensity)
	}
	if command.light.has_range {
		light.range = command.light.range
	}
	id := game.simulation_create_object(
		&session.sim,
		{
			name = name,
			prefab = command.prefab,
			body_mode = command.body,
			center = {command.position[0], command.position[1], command.position[2]},
			yaw_rad = f32(math.to_radians(f64(command.yaw_deg))),
			light = light,
		},
	)
	if id == game.INVALID_OBJECT_ID {
		return format_error("%s", "place failed")
	}
	reply.placed = id
	return ""
}

session_remove :: proc(session: ^Session, command: Remove_Command) -> string {
	id := command.id
	if command.has_name {
		remove_name := command.name
		name := object_name_text(&remove_name)
		object, found := game.simulation_object_find_by_name(&session.sim, name)
		if !found {
			return format_error("object name %q does not exist", name)
		}
		id = object.id
	}
	if !game.simulation_remove_object(&session.sim, id) {
		return format_error("object id %d does not exist", id)
	}
	return ""
}
