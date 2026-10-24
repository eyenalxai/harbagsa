#+vet explicit-allocators
package harness

import "core:encoding/json"

import "src:game"

Editor_Camera :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
}

Editor_Place :: struct {
	prefab:   game.Prefab_Id,
	position: [3]f32,
	yaw:      f32,
	body:     game.Body_Mode,
}

Editor_Command :: struct {
	open:       bool,
	has_open:   bool,
	select:     int,
	has_select: bool,
	body:       game.Body_Mode,
	has_body:   bool,
	pick:       bool,
	height:     f32,
	has_height: bool,
	yaw:        f32,
	has_yaw:    bool,
	snap:       bool,
	has_snap:   bool,
	cancel:     bool,
	camera:     Editor_Camera,
	has_camera: bool,
	place:      Editor_Place,
	has_place:  bool,
	sun:        Editor_Sun,
	has_sun:    bool,
	object:     Editor_Object,
	light:      Editor_Light,
}

parse_editor :: proc(object: json.Object) -> (Command, string) {
	allowed := []string {
		"cmd",
		"open",
		"select",
		"body",
		"pick",
		"height",
		"yaw",
		"snap",
		"cancel",
		"camera",
		"place",
		"sun",
		"select_object",
		"move",
		"rotate",
		"delete",
		"duplicate",
		"undo",
		"redo",
		"light_color",
		"light_intensity",
		"light_range",
	}
	if key, unknown := json_unknown_key(object, allowed); unknown {
		return {}, format_error("unknown key %q", key)
	}

	command := Command{kind = .Editor}
	if value, has := json_get(object, "open"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'open' must be a boolean"
		}
		command.editor.open = flag
		command.editor.has_open = true
	}
	if value, has := json_get(object, "select"); has {
		selected, ok := json_integer(value)
		if !ok || selected < 0 || selected >= game.PREFAB_COUNT {
			return {}, format_error(
				"'select' must be an integer in [0, %d]",
				game.PREFAB_COUNT - 1,
			)
		}
		command.editor.select = selected
		command.editor.has_select = true
	}
	if value, has := json_get(object, "body"); has {
		mode, mode_error := parse_body_mode(value, "body")
		if mode_error != "" {
			return {}, mode_error
		}
		command.editor.body = mode
		command.editor.has_body = true
	}
	if value, has := json_get(object, "pick"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'pick' must be a boolean"
		}
		command.editor.pick = flag
	}
	if value, has := json_get(object, "height"); has {
		height, ok := json_number(value)
		if !ok || height < 0 {
			return {}, "'height' must be a non-negative number"
		}
		command.editor.height = f32(height)
		command.editor.has_height = true
	}
	if value, has := json_get(object, "yaw"); has {
		yaw, ok := json_number(value)
		if !ok {
			return {}, "'yaw' must be a number"
		}
		command.editor.yaw = f32(yaw)
		command.editor.has_yaw = true
	}
	if value, has := json_get(object, "snap"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'snap' must be a boolean"
		}
		command.editor.snap = flag
		command.editor.has_snap = true
	}
	if value, has := json_get(object, "cancel"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'cancel' must be a boolean"
		}
		command.editor.cancel = flag
	}
	if value, has := json_get(object, "camera"); has {
		camera, camera_error := parse_editor_camera(value)
		if camera_error != "" {
			return {}, camera_error
		}
		command.editor.camera = camera
		command.editor.has_camera = true
	}
	if value, has := json_get(object, "place"); has {
		place, place_error := parse_editor_place(value)
		if place_error != "" {
			return {}, place_error
		}
		command.editor.place = place
		command.editor.has_place = true
	}
	if value, has := json_get(object, "sun"); has {
		sun, sun_error := parse_editor_sun(value)
		if sun_error != "" {
			return {}, sun_error
		}
		command.editor.sun = sun
		command.editor.has_sun = true
	}
	editor_object, object_error := parse_editor_object(object)
	if object_error != "" {
		return {}, object_error
	}
	command.editor.object = editor_object
	editor_light, light_error := parse_editor_light(object)
	if light_error != "" {
		return {}, light_error
	}
	command.editor.light = editor_light

	if !editor_command_has_action(object) {
		return {}, "editor needs at least one field"
	}
	return command, ""
}

@(private)
parse_editor_camera :: proc(value: json.Value) -> (Editor_Camera, string) {
	object, ok := json_object(value)
	if !ok {
		return {}, "'camera' must be an object"
	}
	if key, unknown := json_unknown_key(object, {"position", "yaw", "pitch"}); unknown {
		return {}, format_error("unknown editor camera key %q", key)
	}
	position, position_ok := vec3_field(object, "position")
	yaw, yaw_ok := number_field(object, "yaw")
	pitch, pitch_ok := number_field(object, "pitch")
	if !position_ok || !yaw_ok || !pitch_ok {
		return {}, "editor 'camera' needs 'position', 'yaw' and 'pitch'"
	}
	return {position = position, yaw = f32(yaw), pitch = f32(pitch)}, ""
}

@(private)
parse_editor_place :: proc(value: json.Value) -> (Editor_Place, string) {
	object, ok := json_object(value)
	if !ok {
		return {}, "'place' must be an object"
	}
	if key, unknown := json_unknown_key(object, {"prefab", "position", "yaw", "body"}); unknown {
		return {}, format_error("unknown editor place key %q", key)
	}
	name, name_ok := string_field(object, "prefab")
	if !name_ok {
		return {}, "editor 'place' needs a string 'prefab'"
	}
	prefab_id, parsed := game.prefab_parse(name)
	if !parsed {
		return {}, format_error("unknown prefab %q", name)
	}
	position, position_ok := vec3_field(object, "position")
	if !position_ok {
		return {}, "editor 'place' needs a 'position' of three numbers"
	}

	place := Editor_Place {
		prefab = prefab_id,
		position = position,
		body = game.prefab(prefab_id).body_mode,
	}
	if yaw_value, has := json_get(object, "yaw"); has {
		yaw, yaw_ok := json_number(yaw_value)
		if !yaw_ok {
			return {}, "editor 'place' yaw must be a number"
		}
		place.yaw = f32(yaw)
	}
	if body_value, has := json_get(object, "body"); has {
		mode, body_error := parse_body_mode(body_value, "place.body")
		if body_error != "" {
			return {}, body_error
		}
		place.body = mode
	}
	return place, ""
}

@(private)
parse_body_mode :: proc(value: json.Value, label: string) -> (game.Body_Mode, string) {
	name, ok := json_string(value)
	if !ok {
		return .Static, format_error("'%s' must be a string", label)
	}
	mode, parsed := game.body_mode_parse(name)
	if !parsed {
		return .Static, format_error("unknown body mode %q; use 'static' or 'dynamic'", name)
	}
	return mode, ""
}

@(private)
editor_command_has_action :: proc(object: json.Object) -> bool {
	keys := []string {
		"open",
		"select",
		"body",
		"pick",
		"height",
		"yaw",
		"snap",
		"cancel",
		"camera",
		"place",
		"sun",
		"select_object",
		"move",
		"rotate",
		"delete",
		"duplicate",
		"undo",
		"redo",
		"light_color",
		"light_intensity",
		"light_range",
	}
	for key in keys {
		if _, present := json_get(object, key); present {
			return true
		}
	}
	return false
}
