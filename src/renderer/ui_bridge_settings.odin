#+vet explicit-allocators
package renderer

import "src:ui"

Ui_Settings_Options :: struct {
	window_modes: [2]Ui_Option,
	displays:     [ui.SETTINGS_MAX_DISPLAYS]Ui_Option,
	resolutions:  [ui.SETTINGS_MAX_MODES]Ui_Option,
	sprint_modes: [2]Ui_Option,
}

ui_settings_frame :: proc(source: ^ui.Settings, options: ^Ui_Settings_Options) -> Ui_Settings {
	for &option, index in source.window_modes {
		options.window_modes[index] = ui_option(&option)
	}
	display_count := clamp(source.display_count, 0, ui.SETTINGS_MAX_DISPLAYS)
	for index in 0 ..< display_count {
		options.displays[index] = ui_option(&source.display_names[index])
	}
	resolution_count := clamp(source.resolution_count, 0, ui.SETTINGS_MAX_MODES)
	for index in 0 ..< resolution_count {
		options.resolutions[index] = ui_option(&source.resolution_names[index])
	}
	for &option, index in source.sprint_modes {
		options.sprint_modes[index] = ui_option(&option)
	}
	return {
		window_mode = u32(source.window_mode),
		display = u32(source.display),
		resolution = u32(source.resolution),
		sprint_mode = u32(source.sprint_mode),
		hud_opacity = source.hud_opacity,
		reduce_motion = u32(source.reduce_motion),
		window_modes = raw_data(options.window_modes[:]),
		window_mode_count = u32(len(options.window_modes)),
		displays = raw_data(options.displays[:display_count]),
		display_count = u32(display_count),
		resolutions = raw_data(options.resolutions[:resolution_count]),
		resolution_count = u32(resolution_count),
		sprint_modes = raw_data(options.sprint_modes[:]),
		sprint_mode_count = u32(len(options.sprint_modes)),
	}
}

@(private)
ui_option :: proc(source: ^ui.Settings_Option) -> Ui_Option {
	return {
		text = raw_data(source.text[:]),
		length = u32(source.length),
	}
}
