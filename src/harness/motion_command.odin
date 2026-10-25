#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:math"

@(private)
parse_look :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "dx", "dy"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	dx, dx_ok := number_field(object, "dx")
	dy, dy_ok := number_field(object, "dy")
	if !dx_ok || !dy_ok {
		return {}, format_error("%s", "look needs numeric 'dx' and 'dy'")
	}
	return {kind = .Look, look = {dx = f32(dx), dy = f32(dy)}}, ""
}

@(private)
parse_face :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "yaw_deg", "pitch_deg"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	yaw, yaw_ok := number_field(object, "yaw_deg")
	pitch, pitch_ok := number_field(object, "pitch_deg")
	if !yaw_ok || !pitch_ok {
		return {}, format_error("%s", "face needs numeric 'yaw_deg' and 'pitch_deg'")
	}
	return {
		kind = .Face,
		face = {yaw_rad = f32(math.to_radians(yaw)), pitch_rad = f32(math.to_radians(pitch))},
	}, ""
}

@(private)
parse_input :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "forward", "right", "jump"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	input, input_error := parse_input_fields(object)
	if input_error != "" {
		return {}, input_error
	}
	return {kind = .Input, input = input}, ""
}

parse_input_fields :: proc(object: json.Object) -> (input: Input_Command, error: string) {
	if value, has := json_get(object, "forward"); has {
		forward, ok := json_number(value)
		if !ok || forward < -1 || forward > 1 {
			return {}, format_error("%s", "'forward' must be a number in [-1, 1]")
		}
		input.forward = f32(forward)
		input.has_forward = true
	}
	if value, has := json_get(object, "right"); has {
		right, ok := json_number(value)
		if !ok || right < -1 || right > 1 {
			return {}, format_error("%s", "'right' must be a number in [-1, 1]")
		}
		input.right = f32(right)
		input.has_right = true
	}
	if field_error := json_optional_bool(object, "jump", &input.jump, &input.has_jump); field_error != "" {
		return {}, field_error
	}
	return input, ""
}

@(private)
parse_camera :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(
		object,
		{"cmd", "position", "yaw_deg", "pitch_deg", "look_at", "fov_deg", "clear"},
	); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Camera}
	if field_error := json_bool(object, "clear", &command.camera.clear); field_error != "" {
		return {}, field_error
	}
	if command.camera.clear {
		for key, _ in object {
			if key != "cmd" && key != "clear" {
				return {}, format_error("%s", "camera 'clear' cannot be combined with another field")
			}
		}
		return command, ""
	}
	position, position_ok := vec3_field(object, "position")
	if !position_ok {
		return {}, format_error("%s", "camera needs 'position'")
	}
	command.camera.position = position
	angles, angles_error := camera_angles_from_fields(object, position, "camera")
	if angles_error != "" {
		return {}, angles_error
	}
	command.camera.yaw_rad = angles.yaw_rad
	command.camera.pitch_rad = angles.pitch_rad
	command.camera.has_angles = true
	if value, has := json_get(object, "fov_deg"); has {
		fov, fov_ok := json_number(value)
		if !fov_ok || fov < 1 || fov > 170 {
			return {}, format_error("%s", "'fov_deg' must be a number in [1, 170]")
		}
		command.camera.fov_deg = f32(fov)
		command.camera.has_fov = true
	}
	return command, ""
}

Camera_Angles :: struct {
	yaw_rad:   f32,
	pitch_rad: f32,
}

// The camera forward is (-sin yaw cos pitch, sin pitch, -cos yaw cos pitch).
// Solving for that basis removes the hand-computed angles that got a view wrong.
camera_look_at_angles :: proc(position, target: [3]f32) -> (angles: Camera_Angles, ok: bool) {
	delta := target - position
	length := math.sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
	if length <= 1e-6 {
		return {}, false
	}
	direction := delta / length
	angles.pitch_rad = math.asin(clamp(direction.y, -1, 1))
	angles.yaw_rad = math.atan2(-direction.x, -direction.z)
	return angles, true
}

// The camera command and the editor camera share the field rules; the label
// names which command owns the error.
camera_angles_from_fields :: proc(
	object: json.Object,
	position: [3]f32,
	label: string,
) -> (angles: Camera_Angles, error: string) {
	look_at, look_at_ok := vec3_field(object, "look_at")
	yaw, yaw_ok := number_field(object, "yaw_deg")
	pitch, pitch_ok := number_field(object, "pitch_deg")
	if look_at_ok && (yaw_ok || pitch_ok) {
		return {}, format_error("%s takes 'look_at' or 'yaw_deg' and 'pitch_deg', not both", label)
	}
	if look_at_ok {
		computed, ok := camera_look_at_angles(position, look_at)
		if !ok {
			return {}, format_error("%s 'look_at' must differ from 'position'", label)
		}
		return computed, ""
	}
	if !yaw_ok || !pitch_ok {
		return {}, format_error("%s needs 'look_at' or 'yaw_deg' and 'pitch_deg'", label)
	}
	return {
		yaw_rad = f32(math.to_radians(yaw)),
		pitch_rad = f32(math.to_radians(pitch)),
	}, ""
}
