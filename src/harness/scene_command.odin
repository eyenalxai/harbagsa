#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:frame"
import "src:game"

SCENE_KEYS := [?]string{"cmd", "camera", "sun", "objects", "settings", "view", "displays", "renderer_debug"}

Scene_Command :: struct {
	scene:          frame.Scene,
	settings:       Scene_Settings_Patch,
	view:           Scene_View_Patch,
	has_camera:     bool,
	has_sun:        bool,
	has_objects:    bool,
	has_settings:   bool,
	has_view:       bool,
	has_displays:   bool,
	renderer_debug: Maybe(Renderer_Debug_Command),
}

@(private)
parse_scene :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, SCENE_KEYS[:]); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Scene}
	ok := false
	defer if !ok {
		frame.scene_destroy(&command.scene.scene, allocator)
	}
	if value, has := json_get(object, "camera"); has {
		camera, camera_error := parse_scene_camera(value, allocator)
		if camera_error != "" {
			return {}, camera_error
		}
		command.scene.scene.camera = camera
		command.scene.has_camera = true
	}
	if value, has := json_get(object, "sun"); has {
		sun, sun_error := parse_scene_sun(value)
		if sun_error != "" {
			return {}, sun_error
		}
		command.scene.scene.sun = sun
		command.scene.has_sun = true
	}
	if value, has := json_get(object, "objects"); has {
		objects, objects_error := parse_scene_objects(value, allocator)
		if objects_error != "" {
			return {}, objects_error
		}
		command.scene.scene.objects = objects
		command.scene.has_objects = true
	}
	if value, has := json_get(object, "settings"); has {
		settings, settings_error := parse_scene_settings(value, allocator)
		if settings_error != "" {
			return {}, settings_error
		}
		command.scene.settings = settings
		command.scene.has_settings = true
	}
	if value, has := json_get(object, "view"); has {
		view, view_error := parse_scene_view(value)
		if view_error != "" {
			return {}, view_error
		}
		command.scene.view = view
		command.scene.has_view = true
	}
	if value, has := json_get(object, "renderer_debug"); has {
		debug_object, debug_ok := json_object(value)
		if !debug_ok {
			return {}, format_error("%s", "scene 'renderer_debug' must be an object")
		}
		if key, unknown := json_unknown_key(debug_object, RENDERER_DEBUG_BLOCK_KEYS); unknown {
			return {}, format_error("unknown renderer_debug key %q", key)
		}
		fields, fields_error := renderer_debug_fields(debug_object)
		if fields_error != "" {
			return {}, fields_error
		}
		command.scene.renderer_debug = fields
	}
	if value, has := json_get(object, "displays"); has {
		displays, displays_error := parse_scene_displays(value, allocator)
		if displays_error != "" {
			return {}, displays_error
		}
		command.scene.scene.displays = displays
		command.scene.has_displays = true
	}
	_, has_renderer_debug := command.scene.renderer_debug.?
	if !command.scene.has_camera &&
	   !command.scene.has_sun &&
	   !command.scene.has_objects &&
	   !command.scene.has_settings &&
	   !command.scene.has_view &&
	   !command.scene.has_displays &&
	   !has_renderer_debug {
		return {}, format_error("%s", "scene needs at least one block")
	}
	ok = true
	return command, ""
}

@(private)
destroy_scene :: proc(command: ^Command, allocator: mem.Allocator) {
	frame.scene_destroy(&command.scene.scene, allocator)
	if value, has := command.scene.settings.window_mode.?; has {
		delete(value, allocator)
	}
	if value, has := command.scene.settings.sprint_mode.?; has {
		delete(value, allocator)
	}
	if value, has := command.scene.settings.crouch_mode.?; has {
		delete(value, allocator)
	}
	if value, has := command.scene.settings.prone_mode.?; has {
		delete(value, allocator)
	}
	command^ = {}
}

@(private)
parse_scene_camera :: proc(value: json.Value, allocator: mem.Allocator) -> (frame.Scene_Camera, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scene 'camera' must be an object")
	}
	if key, unknown := json_unknown_key(
		object,
		{"source", "position", "yaw_deg", "pitch_deg", "fov_deg", "player"},
	); unknown {
		return {}, format_error("unknown camera key %q", key)
	}
	source, source_ok := string_field(object, "source")
	if !source_ok || (source != "override" && source != "debug" && source != "player") {
		return {}, format_error("%s", "camera 'source' must be override, debug, or player")
	}
	position, position_ok := vec3_field(object, "position")
	yaw, yaw_ok := number_field(object, "yaw_deg")
	pitch, pitch_ok := number_field(object, "pitch_deg")
	if !position_ok || !yaw_ok || !pitch_ok {
		return {}, format_error("%s", "camera needs 'position', 'yaw_deg', and 'pitch_deg'")
	}
	camera := frame.Scene_Camera {
		source = strings.clone(source, allocator),
		position = position,
		yaw_deg = f32(yaw),
		pitch_deg = f32(pitch),
		fov_deg = 90,
	}
	ok := false
	defer if !ok {
		delete(camera.source, allocator)
	}
	if fov, has := number_field(object, "fov_deg"); has {
		if fov < 1 || fov > 170 {
			return {}, format_error("%s", "camera 'fov_deg' must be in [1, 170]")
		}
		camera.fov_deg = f32(fov)
	}
	if player_value, has := json_get(object, "player"); has {
		player, player_error := parse_scene_player(player_value, allocator)
		if player_error != "" {
			return {}, player_error
		}
		camera.player = player
	}
	if source == "player" {
		if _, has_player := camera.player.?; !has_player {
			return {}, format_error("%s", "a player camera needs a 'player' block")
		}
	}
	ok = true
	return camera, ""
}

@(private)
parse_scene_player :: proc(value: json.Value, allocator: mem.Allocator) -> (frame.Scene_Player, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "camera 'player' must be an object")
	}
	if key, unknown := json_unknown_key(object, {"position", "yaw_deg", "pitch_deg", "stance", "velocity", "grounded", "step_smoothing", "eye_height"}); unknown {
		return {}, format_error("unknown player key %q", key)
	}
	position, position_ok := vec3_field(object, "position")
	yaw, yaw_ok := number_field(object, "yaw_deg")
	pitch, pitch_ok := number_field(object, "pitch_deg")
	stance_name, stance_ok := string_field(object, "stance")
	stance, stance_parsed := game.stance_parse(stance_name)
	if !position_ok || !yaw_ok || !pitch_ok || !stance_ok || !stance_parsed {
		return {}, format_error("%s", "player needs 'position', 'yaw_deg', 'pitch_deg', and a valid 'stance'")
	}
	player := frame.Scene_Player {
		position = position,
		yaw_deg = f32(yaw),
		pitch_deg = f32(pitch),
		stance = strings.clone(game.stance_name(stance), allocator),
	}
	if velocity, has := vec3_field(object, "velocity"); has {
		player.velocity = velocity
	}
	if grounded, has := json_get(object, "grounded"); has {
		player.grounded, _ = json_boolean(grounded)
	}
	if step_smoothing, has := number_field(object, "step_smoothing"); has {
		player.step_smoothing = f32(step_smoothing)
	}
	if eye_height, has := number_field(object, "eye_height"); has {
		player.eye_height = f32(eye_height)
	}
	return player, ""
}

@(private)
parse_scene_sun :: proc(value: json.Value) -> (frame.Scene_Sun, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scene 'sun' must be an object")
	}
	if key, unknown := json_unknown_key(object, {"position", "angular_diameter_deg"}); unknown {
		return {}, format_error("unknown sun key %q", key)
	}
	position, position_ok := vec3_field(object, "position")
	diameter, diameter_ok := number_field(object, "angular_diameter_deg")
	if !position_ok || !diameter_ok || diameter <= 0 {
		return {}, format_error("%s", "sun needs 'position' and a positive 'angular_diameter_deg'")
	}
	return {position = position, angular_diameter_deg = f32(diameter)}, ""
}
