#+vet explicit-allocators
package harness

import "core:encoding/json"

// The object editing group. `body` stays on the editor command because it is
// shared with the palette, exactly like the keyboard M key.
Editor_Object :: struct {
	select_object:     u32,
	has_select_object: bool,
	move:              [3]f32,
	has_move:          bool,
	rotate_deg:        f32,
	has_rotate:        bool,
	delete:            bool,
	duplicate:         bool,
	undo:              bool,
	redo:              bool,
}

@(private)
parse_editor_object :: proc(object: json.Object) -> (Editor_Object, string) {
	editor: Editor_Object
	if value, has := json_get(object, "select_object"); has {
		id, ok := json_integer(value)
		if !ok || id < 0 {
			return {}, "'select_object' must be a non-negative integer object id"
		}
		editor.select_object = u32(id)
		editor.has_select_object = true
	}
	if _, has := json_get(object, "move"); has {
		position, ok := vec3_field(object, "move")
		if !ok {
			return {}, "'move' must be a position of three numbers"
		}
		editor.move = position
		editor.has_move = true
	}
	if value, has := json_get(object, "rotate_deg"); has {
		degrees, ok := json_number(value)
		if !ok {
			return {}, "'rotate_deg' must be a number of degrees"
		}
		editor.rotate_deg = f32(degrees)
		editor.has_rotate = true
	}
	if field_error := json_bool(object, "delete", &editor.delete); field_error != "" {
		return {}, field_error
	}
	if field_error := json_bool(object, "duplicate", &editor.duplicate); field_error != "" {
		return {}, field_error
	}
	if field_error := json_bool(object, "undo", &editor.undo); field_error != "" {
		return {}, field_error
	}
	if field_error := json_bool(object, "redo", &editor.redo); field_error != "" {
		return {}, field_error
	}
	return editor, ""
}
