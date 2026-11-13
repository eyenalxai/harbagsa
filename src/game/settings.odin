#+vet explicit-allocators
#+vet !unused-procedures // the harness and the scene load use these names
package game

import "src:display"
import "src:ui"

Settings :: struct {
	window:        display.Window_Settings,
	display:       display.List,
	sprint_mode:   Input_Mode,
	type_weight:   f32,
	hud_opacity:   f32,
	reduce_motion: bool,
}

Settings_Id :: enum {
	Window_Mode,
	Display,
	Resolution,
	Sprint_Mode,
	Hud_Opacity,
	Reduce_Motion,
}

DEFAULT_WINDOW_SETTINGS :: display.Window_Settings {
	mode       = .Borderless,
	display    = 0,
	resolution = {1280, 720},
}

DEFAULT_SETTINGS :: Settings {
	window        = DEFAULT_WINDOW_SETTINGS,
	sprint_mode   = DEFAULT_SPRINT_INPUT_MODE,
	type_weight   = ui.TYPE_WEIGHT_DEFAULT,
	hud_opacity   = ui.HUD_OPACITY_DEFAULT,
	reduce_motion = false,
}

settings_default :: proc() -> Settings {
	return DEFAULT_SETTINGS
}

// settings_set is the one mutation path for the settings dialog, the harness,
// and the remaining menu navigation. It reports whether a value changed.
settings_set :: proc(settings: ^Settings, id: Settings_Id, value: int, scalar: f32) -> bool {
	#partial switch id {
	case .Window_Mode:
		mode: display.Window_Mode
		switch value {
		case 0:
			mode = .Borderless
		case 1:
			mode = .Windowed
		case:
			return false
		}
		if settings.window.mode == mode {
			return false
		}
		settings.window.mode = mode
	case .Display:
		if value < 0 || value >= settings.display.count {
			return false
		}
		if settings.window.display == value {
			return false
		}
		settings.window.display = value
		info := display.info_at(&settings.display, value)
		settings.window.resolution = display.snap_mode(info, settings.window.resolution)
	case .Resolution:
		info := display.info_at(&settings.display, settings.window.display)
		if value < 0 || value >= info.mode_count {
			return false
		}
		mode := info.modes[value]
		if settings.window.mode == .Windowed && settings.window.resolution == mode {
			return false
		}
		settings.window.mode = .Windowed
		settings.window.resolution = mode
	case .Sprint_Mode:
		mode: Input_Mode
		switch value {
		case 0:
			mode = .Hold
		case 1:
			mode = .Toggle
		case:
			return false
		}
		if settings.sprint_mode == mode {
			return false
		}
		settings.sprint_mode = mode
	case .Hud_Opacity:
		next := clamp(scalar, ui.HUD_OPACITY_MIN, ui.HUD_OPACITY_MAX)
		if next == settings.hud_opacity {
			return false
		}
		settings.hud_opacity = next
	case .Reduce_Motion:
		next := value != 0
		if next == settings.reduce_motion {
			return false
		}
		settings.reduce_motion = next
	case:
		return false
	}
	return true
}

input_mode_name :: proc(mode: Input_Mode) -> string {
	return mode == .Hold ? "Hold" : "Toggle"
}

input_mode_parse :: proc(name: string) -> (Input_Mode, bool) {
	switch name {
	case "Hold":
		return .Hold, true
	case "Toggle":
		return .Toggle, true
	}
	return .Hold, false
}

toggle_input_mode :: proc(mode: Input_Mode) -> Input_Mode {
	return mode == .Hold ? .Toggle : .Hold
}

window_mode_name :: proc(mode: display.Window_Mode) -> string {
	return mode == .Borderless ? "Borderless" : "Windowed"
}

window_mode_parse :: proc(name: string) -> (display.Window_Mode, bool) {
	switch name {
	case "Borderless":
		return .Borderless, true
	case "Windowed":
		return .Windowed, true
	}
	return .Borderless, false
}

toggle_window_mode :: proc(mode: display.Window_Mode) -> display.Window_Mode {
	return mode == .Borderless ? .Windowed : .Borderless
}

settings_display_name :: proc(settings: ^Settings) -> string {
	if settings.display.count == 0 {
		return "Display 1"
	}
	info := display.info_at(&settings.display, settings.window.display)
	return display.name(info)
}

settings_effective_resolution :: proc(settings: ^Settings) -> display.Mode {
	if settings.display.count == 0 {
		return settings.window.resolution
	}
	info := display.info_at(&settings.display, settings.window.display)
	if settings.window.mode == .Borderless {
		return info.desktop
	}
	return settings.window.resolution
}
