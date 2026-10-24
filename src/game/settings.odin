#+vet explicit-allocators
package game

Settings :: struct {
	sprint_mode: Input_Mode,
	crouch_mode: Input_Mode,
	prone_mode:  Input_Mode,
}

DEFAULT_SETTINGS :: Settings {
	sprint_mode = DEFAULT_SPRINT_INPUT_MODE,
	crouch_mode = DEFAULT_CROUCH_INPUT_MODE,
	prone_mode  = DEFAULT_PRONE_INPUT_MODE,
}

settings_default :: proc() -> Settings {
	return DEFAULT_SETTINGS
}

input_mode_name :: proc(mode: Input_Mode) -> string {
	return mode == .Hold ? "Hold" : "Toggle"
}

toggle_input_mode :: proc(mode: Input_Mode) -> Input_Mode {
	return mode == .Hold ? .Toggle : .Hold
}
