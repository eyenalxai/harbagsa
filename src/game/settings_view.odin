#+vet explicit-allocators
package game

import "core:fmt"

import "src:display"
import "src:ui"

// settings_view names every option and reports the current index, so the Rune
// view never derives a display or mode name from game state.
settings_view :: proc(settings: ^Settings) -> ui.Settings {
	view := ui.Settings {
		hud_opacity   = settings.hud_opacity,
		reduce_motion = settings.reduce_motion,
	}
	settings_option_set(&view.window_modes[0], window_mode_name(.Borderless))
	settings_option_set(&view.window_modes[1], window_mode_name(.Windowed))
	view.window_mode = settings.window.mode == .Borderless ? 0 : 1
	settings_option_set(&view.sprint_modes[0], input_mode_name(.Hold))
	settings_option_set(&view.sprint_modes[1], input_mode_name(.Toggle))
	view.sprint_mode = settings.sprint_mode == .Hold ? 0 : 1

	view.display_count = min(settings.display.count, ui.SETTINGS_MAX_DISPLAYS)
	for index in 0 ..< view.display_count {
		settings_option_set(&view.display_names[index], display.name(&settings.display.items[index]))
	}
	view.display = display.clamp_index(&settings.display, settings.window.display)

	info := display.info_at(&settings.display, view.display)
	view.resolution_count = min(info.mode_count, ui.SETTINGS_MAX_MODES)
	for index in 0 ..< view.resolution_count {
		settings_option_mode(&view.resolution_names[index], info.modes[index])
	}
	current := settings.window.mode == .Borderless ? info.desktop : settings.window.resolution
	index := display.find_mode(info, current)
	view.resolution = max(index, 0)
	return view
}

@(private)
settings_option_set :: proc(option: ^ui.Settings_Option, text: string) {
	count := min(len(text), len(option.text))
	for count > 0 && count < len(text) && (text[count] & 0xc0) == 0x80 {
		count -= 1
	}
	copy(option.text[:], text[:count])
	option.length = count
}

@(private)
settings_option_mode :: proc(option: ^ui.Settings_Option, mode: display.Mode) {
	text := fmt.bprintf(option.text[:], "%d×%d", mode.width, mode.height)
	option.length = len(text)
}
