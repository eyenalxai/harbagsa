#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"

// A shot is a scenario-only shorthand. It compiles to the explicit camera, sun,
// settle, and capture commands before the run starts, so the command list stays
// deterministic and a live session never sees it.
SHOT_KEYS := []string {
	"cmd",
	"name",
	"note",
	"camera",
	"sun",
	"settle",
	"frame",
	"alpha",
	"target",
	"format",
	"png",
	"region",
	"rect",
	"profile",
	"crop",
	"histogram",
	"steps",
	"color_key",
}

scenario_shot :: proc(
	object: json.Object,
	commands: ^[dynamic]Command,
	allocator: mem.Allocator,
) -> string {
	if key, unknown := json_unknown_key(object, SHOT_KEYS); unknown {
		return fmt.aprintf("shot has unknown key %q", key, allocator = allocator)
	}
	name, has_name := string_field(object, "name")
	if !has_name || !valid_capture_name(name) {
		return format_error("%s", "shot 'name' must use only letters, digits, '-' and '_'")
	}
	if value, has := json_get(object, "note"); has {
		if _, ok := json_string(value); !ok {
			return format_error("%s", "shot 'note' must be a string")
		}
	}

	start := len(commands^)
	ok := false
	defer if !ok {
		for index in start ..< len(commands^) {
			command_destroy(&commands[index], allocator)
		}
		resize(commands, start)
	}

	if camera_value, has := json_get(object, "camera"); has {
		camera_object, camera_ok := json_object(camera_value)
		if !camera_ok {
			return format_error("%s", "shot 'camera' must be an object")
		}
		synthetic := with_command(camera_object, "camera")
		command, error := parse_camera(synthetic, allocator)
		if error != "" {
			return error
		}
		append(commands, command)
	}

	if sun_value, has := json_get(object, "sun"); has {
		sun_object, sun_ok := json_object(sun_value)
		if !sun_ok {
			return format_error("%s", "shot 'sun' must be an object")
		}
		synthetic := with_command(sun_object, "sun")
		command, error := parse_sun(synthetic, allocator)
		if error != "" {
			return error
		}
		append(commands, command)
	}

	if settle_value, has := json_get(object, "settle"); has {
		command, error := shot_settle(settle_value)
		if error != "" {
			return error
		}
		append(commands, command)
	}

	capture_object := make(json.Object, len(object) + 1, context.temp_allocator)
	for key, value in object {
		switch key {
		case "cmd", "camera", "sun", "settle":
			continue
		}
		capture_object[key] = value
	}
	capture_object["cmd"] = json.String("capture")
	capture_object["name"] = json.String(name)
	command, error := parse_capture(capture_object, allocator)
	if error != "" {
		return error
	}
	append(commands, command)
	ok = true
	return ""
}

@(private)
shot_settle :: proc(value: json.Value) -> (Command, string) {
	if frames, ok := json_integer(value); ok {
		if frames < 1 || frames > MAX_STEP_FRAMES {
			return {}, format_error("shot 'settle' must be in [1, %d]", MAX_STEP_FRAMES)
		}
		return {kind = .Settle, settle = {frames = int(frames), has_frames = true}}, ""
	}
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "shot 'settle' must be a frame count or an object")
	}
	return parse_settle(with_command(object, "settle"), context.allocator)
}

@(private)
with_command :: proc(object: json.Object, command: string) -> json.Object {
	result := make(json.Object, len(object) + 1, context.temp_allocator)
	for key, value in object {
		result[key] = value
	}
	result["cmd"] = json.String(command)
	return result
}
