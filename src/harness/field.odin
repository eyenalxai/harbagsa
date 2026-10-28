#+vet explicit-allocators
package harness

import "core:strings"

Value_Kind :: enum {
	Number,
	Bool,
	String,
}

Field_Value :: struct {
	kind:    Value_Kind,
	number:  f64,
	boolean: bool,
	text:    string,
}

field_value :: proc(
	state: State,
	captures: []Capture_Result,
	path: string,
) -> (
	Field_Value,
	string,
) {
	if strings.has_prefix(path, "capture.") {
		if len(captures) == 0 {
			return {}, format_error("%s", "no capture has run")
		}
		return capture_path_field(captures, path[len("capture."):])
	}
	return state_field(state, path)
}
