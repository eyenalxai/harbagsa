#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls the menu reset and selection API
package game

import "src:display"
import "src:ui"

MENU_ITEM_COUNT :: 7
MENU_HINT_COUNT :: ui.SETTINGS_HINT_COUNT

MENU_TITLE :: "Settings"
MENU_SUMMARY :: "Window, interface, and controls"
MENU_STATUS_ONE_DISPLAY :: "One display · nothing to change"
MENU_STATUS_NO_MODES :: "No modes · nothing to change"
MENU_STATUS_ONE_MODE :: "One mode · nothing to change"
MENU_STATUS_MODE_MISSING :: "Current mode is not listed · nothing to change"
MENU_STATUS_MIN_OPACITY :: "Minimum opacity · nothing to change"
MENU_STATUS_MAX_OPACITY :: "Maximum opacity · nothing to change"
MENU_WINDOW_APPLY_FAILED :: "Window change failed · %s"
MENU_WINDOW_RESTORE_FAILED :: "Window change failed · %s · restore failed"
MENU_LINE_STATUS :: 0

MENU_ITEM_NAMES := [MENU_ITEM_COUNT]string {
	"Window mode",
	"Display",
	"Resolution",
	"HUD opacity",
	"Sprint mode",
	"Reduce motion",
	"Resume",
}

Menu_Item :: enum {
	Window_Mode,
	Display,
	Resolution,
	Hud_Opacity,
	Sprint,
	Reduce_Motion,
	Resume,
}

Change_Result :: enum {
	Not_A_Setting,
	Changed,
	Blocked,
}

Menu_State :: struct {
	open:            bool,
	selected:        Menu_Item,
	view:            ui.Menu,
	hints:           [MENU_HINT_COUNT]ui.Hint_Cell,
	storage:         Line_Buffer,
	status:          string,
	status_remaining: f32,
}

menu_open :: proc(menu: ^Menu_State) {
	menu.open = true
}

menu_close :: proc(menu: ^Menu_State) {
	menu.open = false
	menu_clear_status(menu)
	menu.view = {}
}

menu_reset :: proc(menu: ^Menu_State) {
	menu^ = {}
}

menu_move :: proc(menu: ^Menu_State, direction: int) {
	if !menu.open || direction == 0 {
		return
	}
	index := (int(menu.selected) + direction + MENU_ITEM_COUNT) % MENU_ITEM_COUNT
	menu.selected = Menu_Item(index)
}

menu_select :: proc(menu: ^Menu_State, index: int) {
	if index >= 0 && index < MENU_ITEM_COUNT {
		menu.selected = Menu_Item(index)
	}
}

menu_selected_name :: proc(menu: ^Menu_State) -> string {
	return MENU_ITEM_NAMES[menu.selected]
}

menu_item_from_name :: proc(name: string) -> (Menu_Item, bool) {
	for index in 0 ..< MENU_ITEM_COUNT {
		if MENU_ITEM_NAMES[index] == name {
			return Menu_Item(index), true
		}
	}
	return .Window_Mode, false
}

// menu_change_setting is the harness's keyboard path. The live dialog sends
// Settings_Set actions, and both paths mutate through settings_set.
menu_change_setting :: proc(
	menu: ^Menu_State,
	settings: ^Settings,
	direction: int,
) -> Change_Result {
	if !menu.open || menu.selected == .Resume || direction == 0 {
		return .Not_A_Setting
	}
	menu_clear_status(menu)
	#partial switch menu.selected {
	case .Window_Mode:
		settings_set(settings, .Window_Mode, int(toggle_window_mode(settings.window.mode)), 0)
	case .Display:
		if settings_display_blocked(settings) {
			menu_set_status(menu, MENU_STATUS_ONE_DISPLAY)
			return .Blocked
		}
		current := display.clamp_index(&settings.display, settings.window.display)
		next := (current + direction + settings.display.count) % settings.display.count
		settings_set(settings, .Display, next, 0)
	case .Resolution:
		info := display.info_at(&settings.display, settings.window.display)
		if settings.display.count == 0 || info.mode_count == 0 {
			menu_set_status(menu, MENU_STATUS_NO_MODES)
			return .Blocked
		}
		if settings_resolution_missing(settings) {
			menu_set_status(menu, MENU_STATUS_MODE_MISSING)
			return .Blocked
		}
		if settings.window.mode == .Windowed && info.mode_count == 1 {
			menu_set_status(menu, MENU_STATUS_ONE_MODE)
			return .Blocked
		}
		current := settings_resolution_current(settings)
		index := display.find_mode(info, current)
		index = (index + direction + info.mode_count) % info.mode_count
		settings_set(settings, .Resolution, index, 0)
	case .Hud_Opacity:
		next := clamp(
			settings.hud_opacity + f32(direction) * 0.01,
			ui.HUD_OPACITY_MIN,
			ui.HUD_OPACITY_MAX,
		)
		if next == settings.hud_opacity {
			status := direction > 0 ? MENU_STATUS_MAX_OPACITY : MENU_STATUS_MIN_OPACITY
			menu_set_status(menu, status)
			return .Blocked
		}
		settings_set(settings, .Hud_Opacity, 0, next)
	case .Sprint:
		settings_set(settings, .Sprint_Mode, int(toggle_input_mode(settings.sprint_mode)), 0)
	case .Reduce_Motion:
		settings_set(settings, .Reduce_Motion, settings.reduce_motion ? 0 : 1, 0)
	}
	return .Changed
}

menu_activate :: proc(menu: ^Menu_State, settings: ^Settings, direction := 1) -> bool {
	if !menu.open {
		return false
	}
	if menu_change_setting(menu, settings, direction) != .Not_A_Setting {
		return false
	}
	if menu.selected == .Resume {
		menu_close(menu)
		return true
	}
	return false
}

@(private)
menu_set_status :: proc(menu: ^Menu_State, status: string) {
	menu.status = status
	menu.status_remaining = MENU_STATUS_SECONDS
}

menu_clear_status :: proc(menu: ^Menu_State) {
	menu.status = ""
	menu.status_remaining = 0
}

menu_window_apply_failed :: proc(menu: ^Menu_State, reason: string, restored: bool) {
	format := restored ? MENU_WINDOW_APPLY_FAILED : MENU_WINDOW_RESTORE_FAILED
	menu_set_status(menu, line_format(&menu.storage, MENU_LINE_STATUS, format, reason))
}

menu_view :: proc(menu: ^Menu_State, debug_active: bool, delta_seconds: f32) {
	if !menu.open {
		menu.view = {}
		return
	}

	hints := MENU_CONTROL_HINTS
	if debug_active {
		hints = MENU_DEBUG_CONTROL_HINTS
	}
	menu.hints = hints

	if menu.status != "" {
		menu.status_remaining = max(menu.status_remaining - delta_seconds, 0)
		if menu.status_remaining <= 0 {
			menu_clear_status(menu)
		}
	}
	note := menu.status
	if note == "" {
		note = MENU_SUMMARY
	}

	menu.view = {
		title = MENU_TITLE,
		hints = menu.hints[:MENU_HINT_COUNT],
		note  = note,
	}
}
