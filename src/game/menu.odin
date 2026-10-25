#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls the menu reset and selection API
package game

import "core:math"

import "src:display"
import "src:ui"

MENU_ITEM_COUNT :: 8
MENU_ROW_COUNT :: 10
MENU_ROW_DIVIDER :: 7
MENU_ROW_RESUME :: 8
MENU_ROW_HEADER :: 9
MENU_HINT_COLUMNS :: 3
MENU_CONTROL_HINT_COUNT :: 19
MENU_HINT_COUNT :: 23
TYPE_WEIGHT_STEP :: f32(10)

MENU_TITLE :: "Settings"
MENU_NOTE :: "Up/Down select · Left/Right change · Drag slider · Enter change · Esc close"
MENU_STATUS_ONE_DISPLAY :: "One display · nothing to change"
MENU_STATUS_NO_MODES :: "No modes · nothing to change"
MENU_STATUS_ONE_MODE :: "One mode · nothing to change"
MENU_STATUS_MIN_WEIGHT :: "Minimum weight · nothing to change"
MENU_STATUS_MAX_WEIGHT :: "Maximum weight · nothing to change"

MENU_ITEM_NAMES := [MENU_ITEM_COUNT]string {
	"Window mode",
	"Display",
	"Resolution",
	"Type weight",
	"Sprint mode",
	"Crouch mode",
	"Prone mode",
	"Resume",
}

// One row per menu item, in item order, so the harness item name and the
// drawn row index stay independent of where the dividers sit.
MENU_ITEM_ROWS := [MENU_ITEM_COUNT]int{0, 1, 2, 3, 4, 5, 6, MENU_ROW_RESUME}

Menu_Item :: enum {
	Window_Mode,
	Display,
	Resolution,
	Type_Weight,
	Sprint,
	Crouch,
	Prone,
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
	rows:            [MENU_ROW_COUNT]ui.Row,
	hints:           [MENU_HINT_COUNT]ui.Hint_Cell,
	storage:         Line_Buffer,
	displays:        display.List,
	dragging_weight:  bool,
	status:           string,
	status_remaining: f32,
}

menu_open :: proc(menu: ^Menu_State) {
	menu.open = true
	menu.dragging_weight = false
}

menu_close :: proc(menu: ^Menu_State) {
	menu.open = false
	menu.dragging_weight = false
	menu_clear_status(menu)
	menu.view = {}
}

// The display snapshot belongs to the window, not to a menu session.
menu_reset :: proc(menu: ^Menu_State) {
	displays := menu.displays
	menu^ = {}
	menu.displays = displays
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
		settings.window.mode = toggle_window_mode(settings.window.mode)
	case .Display:
		if menu.displays.count <= 1 {
			menu_set_status(menu, MENU_STATUS_ONE_DISPLAY)
			return .Blocked
		}
		change_display(menu, settings, direction)
	case .Resolution:
		info := display.info_at(&menu.displays, settings.window.display)
		if info.mode_count == 0 {
			menu_set_status(menu, MENU_STATUS_NO_MODES)
			return .Blocked
		}
		if settings.window.mode == .Windowed && info.mode_count == 1 {
			menu_set_status(menu, MENU_STATUS_ONE_MODE)
			return .Blocked
		}
		change_resolution(menu, settings, direction)
	case .Type_Weight:
		weight := clamp(
			settings.type_weight + f32(direction) * TYPE_WEIGHT_STEP,
			ui.TYPE_WEIGHT_MIN,
			ui.TYPE_WEIGHT_MAX,
		)
		if weight == settings.type_weight {
			menu_set_status(menu, direction > 0 ? MENU_STATUS_MAX_WEIGHT : MENU_STATUS_MIN_WEIGHT)
			return .Blocked
		}
		settings.type_weight = weight
	case .Sprint:
		settings.sprint_mode = toggle_input_mode(settings.sprint_mode)
	case .Crouch:
		settings.crouch_mode = toggle_input_mode(settings.crouch_mode)
	case .Prone:
		settings.prone_mode = toggle_input_mode(settings.prone_mode)
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

@(private)
menu_clear_status :: proc(menu: ^Menu_State) {
	menu.status = ""
	menu.status_remaining = 0
}

menu_view :: proc(menu: ^Menu_State, settings: Settings, debug_active: bool, delta_seconds: f32) {
	if !menu.open {
		menu.view = {}
		return
	}

	resolution := settings_effective_resolution(settings, &menu.displays)
	menu_setting_row(menu, 0, MENU_ITEM_NAMES[0], window_mode_name(settings.window.mode))
	menu_setting_row(menu, 1, MENU_ITEM_NAMES[1], settings_display_name(settings, &menu.displays))
	menu_setting_row(
		menu,
		2,
		MENU_ITEM_NAMES[2],
		line_format(&menu.storage, 2, "%d×%d", resolution.width, resolution.height),
		numeric = true,
	)
	menu.rows[3] = {
		kind    = .Slider,
		label   = MENU_ITEM_NAMES[3],
		value   = line_format(&menu.storage, 3, "%d", int(math.round(settings.type_weight))),
		numeric = true,
		ratio   = (settings.type_weight - ui.TYPE_WEIGHT_MIN) / (ui.TYPE_WEIGHT_MAX - ui.TYPE_WEIGHT_MIN),
		ticks   = 9,
	}
	menu_setting_row(menu, 4, MENU_ITEM_NAMES[4], input_mode_name(settings.sprint_mode))
	menu_setting_row(menu, 5, MENU_ITEM_NAMES[5], input_mode_name(settings.crouch_mode))
	menu_setting_row(menu, 6, MENU_ITEM_NAMES[6], input_mode_name(settings.prone_mode))
	menu.rows[MENU_ROW_DIVIDER] = {kind = .Divider}
	menu.rows[MENU_ROW_RESUME] = {kind = .Action, label = MENU_ITEM_NAMES[7]}
	menu.rows[MENU_ROW_HEADER] = {kind = .Header, label = "Controls"}

	info := display.info_at(&menu.displays, settings.window.display)
	menu.rows[1].blocked = menu.displays.count <= 1
	menu.rows[2].blocked =
		info.mode_count == 0 ||
		(settings.window.mode == .Windowed && info.mode_count == 1)

	hints := MENU_CONTROL_HINTS
	hint_count := MENU_CONTROL_HINT_COUNT
	if debug_active {
		hints = MENU_DEBUG_CONTROL_HINTS
		hint_count = MENU_HINT_COUNT
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
		note = MENU_NOTE
	}

	menu.view = {
		title        = MENU_TITLE,
		rows         = menu.rows[:],
		selected     = MENU_ITEM_ROWS[menu.selected],
		hints        = menu.hints[:hint_count],
		hint_columns = MENU_HINT_COLUMNS,
		note         = note,
	}
}

@(private)
menu_setting_row :: proc(menu: ^Menu_State, row: int, label, value: string, numeric := false) {
	menu.rows[row] = {kind = .Setting, label = label, value = value, numeric = numeric}
}

@(private)
change_display :: proc(menu: ^Menu_State, settings: ^Settings, direction: int) {
	current := display.clamp_index(&menu.displays, settings.window.display)
	settings.window.display = (current + direction + menu.displays.count) % menu.displays.count
	settings.window.resolution = display.snap_mode(
		display.info_at(&menu.displays, settings.window.display),
		settings.window.resolution,
	)
}

@(private)
change_resolution :: proc(menu: ^Menu_State, settings: ^Settings, direction: int) {
	info := display.info_at(&menu.displays, settings.window.display)
	// A desktop-sized borderless window has no smaller alternatives, so choosing
	// a size always starts a window.
	if settings.window.mode == .Borderless {
		settings.window.mode = .Windowed
		settings.window.resolution = display.cycle_mode(info, info.desktop, direction)
		return
	}
	settings.window.resolution = display.cycle_mode(info, settings.window.resolution, direction)
}
