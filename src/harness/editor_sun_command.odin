#+vet explicit-allocators
package harness

import "core:encoding/json"

Editor_Sun :: struct {
	active:       bool,
	has_active:   bool,
	position:     [3]f32,
	has_position: bool,
	place:        bool,
	cancel:       bool,
}

@(private)
parse_editor_sun :: proc(value: json.Value) -> (Editor_Sun, string) {
	object, ok := json_object(value)
	if !ok {
		return {}, format_error("%s", "'sun' must be an object")
	}
	if key, unknown := json_unknown_key(object, {"active", "position", "place", "cancel"}); unknown {
		return {}, format_error("unknown editor sun key %q", key)
	}

	sun: Editor_Sun
	has_action := false
	if active_value, has := json_get(object, "active"); has {
		flag, flag_ok := json_boolean(active_value)
		if !flag_ok {
			return {}, format_error("%s", "'sun.active' must be a boolean")
		}
		sun.active = flag
		sun.has_active = true
		has_action = true
	}
	if _, has := json_get(object, "position"); has {
		position, position_ok := vec3_field(object, "position")
		if !position_ok {
			return {}, format_error("%s", "'sun.position' must be a position of three numbers")
		}
		sun.position = position
		sun.has_position = true
		has_action = true
	}
	if place_value, has := json_get(object, "place"); has {
		flag, flag_ok := json_boolean(place_value)
		if !flag_ok {
			return {}, format_error("%s", "'sun.place' must be a boolean")
		}
		sun.place = flag
		has_action = true
	}
	if cancel_value, has := json_get(object, "cancel"); has {
		flag, flag_ok := json_boolean(cancel_value)
		if !flag_ok {
			return {}, format_error("%s", "'sun.cancel' must be a boolean")
		}
		sun.cancel = flag
		has_action = true
	}
	if !has_action {
		return {}, format_error("%s", "editor 'sun' needs at least one field")
	}
	return sun, ""
}
