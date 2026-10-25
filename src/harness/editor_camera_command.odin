#+vet explicit-allocators
package harness

import "core:encoding/json"

@(private)
parse_editor_camera :: proc(value: json.Value) -> (Editor_Camera, string) {
	object, ok := json_object(value)
	if !ok {
		return {}, "'camera' must be an object"
	}
	if key, unknown := json_unknown_key(
		object,
		{"position", "look_at", "yaw", "pitch"},
	); unknown {
		return {}, format_error("unknown editor camera key %q", key)
	}
	position, position_ok := vec3_field(object, "position")
	if !position_ok {
		return {}, "editor 'camera' needs a 'position' of three numbers"
	}
	look_at, look_at_ok := vec3_field(object, "look_at")
	yaw, yaw_ok := number_field(object, "yaw")
	pitch, pitch_ok := number_field(object, "pitch")
	if look_at_ok && (yaw_ok || pitch_ok) {
		return {}, "editor 'camera' takes 'look_at' or 'yaw' and 'pitch', not both"
	}
	if look_at_ok {
		angles, angles_ok := camera_look_at_angles(position, look_at)
		if !angles_ok {
			return {}, "editor 'camera' look_at must differ from position"
		}
		return {position = position, yaw = angles.yaw, pitch = angles.pitch}, ""
	}
	if !yaw_ok || !pitch_ok {
		return {}, "editor 'camera' needs 'look_at' or 'yaw' and 'pitch'"
	}
	return {position = position, yaw = f32(yaw), pitch = f32(pitch)}, ""
}
