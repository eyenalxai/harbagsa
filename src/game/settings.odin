#+vet explicit-allocators
package game

import "src:display"

Settings :: struct {
	window:      display.Window_Settings,
	sprint_mode: Input_Mode,
	crouch_mode: Input_Mode,
	prone_mode:  Input_Mode,
}

DEFAULT_WINDOW_SETTINGS :: display.Window_Settings {
	mode       = .Borderless,
	display    = 0,
	resolution = {1280, 720},
}

DEFAULT_SETTINGS :: Settings {
	window      = DEFAULT_WINDOW_SETTINGS,
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

window_mode_name :: proc(mode: display.Window_Mode) -> string {
	return mode == .Borderless ? "Borderless" : "Windowed"
}

toggle_window_mode :: proc(mode: display.Window_Mode) -> display.Window_Mode {
	return mode == .Borderless ? .Windowed : .Borderless
}

settings_display_name :: proc(settings: Settings, displays: ^display.List) -> string {
	if displays == nil || displays.count == 0 {
		return "Display 1"
	}
	info := display.info_at(displays, settings.window.display)
	return display.name(info)
}

settings_effective_resolution :: proc(
	settings: Settings,
	displays: ^display.List,
) -> display.Mode {
	if displays == nil || displays.count == 0 {
		return settings.window.resolution
	}
	info := display.info_at(displays, settings.window.display)
	if settings.window.mode == .Borderless {
		return info.desktop
	}
	return settings.window.resolution
}
