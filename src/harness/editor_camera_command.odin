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
	angles, angles_error := camera_angles_from_fields(object, position, "editor 'camera'")
	if angles_error != "" {
		return {}, angles_error
	}
	return {position = position, yaw = angles.yaw, pitch = angles.pitch}, ""
}
