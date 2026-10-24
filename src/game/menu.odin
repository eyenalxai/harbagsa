#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls the menu reset and selection API
package game

import "src:display"
import "src:ui"

MENU_ITEM_COUNT :: 7
MENU_ROW_COUNT :: 9
MENU_ROW_DIVIDER :: 6
MENU_ROW_RESUME :: 7
MENU_ROW_HEADER :: 8
MENU_HINT_COLUMNS :: 3
MENU_HINT_COUNT :: 18

MENU_TITLE :: "Settings"
MENU_NOTE :: "Up/Down select · Left/Right change · Enter change · Esc close"

MENU_ITEM_NAMES := [MENU_ITEM_COUNT]string {
	"Window mode",
	"Display",
	"Resolution",
	"Sprint mode",
	"Crouch mode",
	"Prone mode",
	"Resume",
}

// One row per menu item, in item order, so the harness `select` index and the
// drawn row index stay independent of where the dividers sit.
MENU_ITEM_ROWS := [MENU_ITEM_COUNT]int{0, 1, 2, 3, 4, 5, MENU_ROW_RESUME}

MENU_CONTROL_HINTS := [MENU_HINT_COUNT]ui.Hint_Cell {
	{keys = "WASD", action = "move"},
	{keys = "Mouse", action = "look"},
	{keys = "Click", action = "capture"},
	{keys = "Shift", action = "sprint"},
	{keys = "Space", action = "jump or hold to mantle"},
	{},
	{keys = "C", action = "crouch or slide"},
	{keys = "Z", action = "prone, crawl, or dive"},
	{},
	{keys = "R", action = "reset"},
	{keys = "Shift+R", action = "scene"},
	{keys = "F1", action = "debug view"},
	{keys = "F2", action = "debug mode"},
	{keys = "F3", action = "TAA"},
	{keys = "F4", action = "perf"},
	{keys = "Esc", action = "settings"},
	{},
	{},
}

MENU_DEBUG_CONTROL_HINTS := [MENU_HINT_COUNT]ui.Hint_Cell {
	{keys = "WASD", action = "fly"},
	{keys = "Space", action = "up"},
	{keys = "Ctrl", action = "down"},
	{keys = "Click", action = "select"},
	{keys = "Drag", action = "move"},
	{keys = "Wheel", action = "height"},
	{keys = "E", action = "add"},
	{keys = "Delete or X", action = "remove"},
	{keys = "L", action = "sun"},
	{keys = "R", action = "reset player"},
	{keys = "F2", action = "exit"},
	{keys = "Shift+R", action = "scene"},
	{keys = "F1", action = "debug view"},
	{keys = "F3", action = "TAA"},
	{keys = "F4", action = "perf"},
	{keys = "Esc", action = "settings"},
	{},
	{},
}

Menu_Item :: enum {
	Window_Mode,
	Display,
	Resolution,
	Sprint,
	Crouch,
	Prone,
	Resume,
}

Menu_State :: struct {
	open:     bool,
	selected: Menu_Item,
	view:     ui.Menu,
	rows:     [MENU_ROW_COUNT]ui.Row,
	hints:    [MENU_HINT_COUNT]ui.Hint_Cell,
	storage:  Line_Buffer,
	displays: display.List,
}

menu_open :: proc(menu: ^Menu_State) {
	menu.open = true
}

menu_close :: proc(menu: ^Menu_State) {
	menu.open = false
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

menu_change_setting :: proc(menu: ^Menu_State, settings: ^Settings, direction: int) -> bool {
	if !menu.open || menu.selected == .Resume || direction == 0 {
		return false
	}
	#partial switch menu.selected {
	case .Window_Mode:
		settings.window.mode = toggle_window_mode(settings.window.mode)
	case .Display:
		change_display(menu, settings, direction)
	case .Resolution:
		change_resolution(menu, settings, direction)
	case .Sprint:
		settings.sprint_mode = toggle_input_mode(settings.sprint_mode)
	case .Crouch:
		settings.crouch_mode = toggle_input_mode(settings.crouch_mode)
	case .Prone:
		settings.prone_mode = toggle_input_mode(settings.prone_mode)
	}
	return true
}

menu_activate :: proc(menu: ^Menu_State, settings: ^Settings, direction := 1) -> bool {
	if !menu.open {
		return false
	}
	if menu_change_setting(menu, settings, direction) {
		return false
	}
	if menu.selected == .Resume {
		menu_close(menu)
		return true
	}
	return false
}

menu_view :: proc(menu: ^Menu_State, settings: Settings, debug_active: bool) {
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
	menu_setting_row(menu, 3, MENU_ITEM_NAMES[3], input_mode_name(settings.sprint_mode))
	menu_setting_row(menu, 4, MENU_ITEM_NAMES[4], input_mode_name(settings.crouch_mode))
	menu_setting_row(menu, 5, MENU_ITEM_NAMES[5], input_mode_name(settings.prone_mode))
	menu.rows[MENU_ROW_DIVIDER] = {kind = .Divider}
	menu.rows[MENU_ROW_RESUME] = {kind = .Action, label = MENU_ITEM_NAMES[6]}
	menu.rows[MENU_ROW_HEADER] = {kind = .Header, label = "Controls"}

	hints := MENU_CONTROL_HINTS
	if debug_active {
		hints = MENU_DEBUG_CONTROL_HINTS
	}
	menu.hints = hints

	menu.view = {
		title        = MENU_TITLE,
		rows         = menu.rows[:],
		selected     = MENU_ITEM_ROWS[menu.selected],
		hints        = menu.hints[:],
		hint_columns = MENU_HINT_COLUMNS,
		note         = MENU_NOTE,
	}
}

@(private)
menu_setting_row :: proc(menu: ^Menu_State, row: int, label, value: string, numeric := false) {
	menu.rows[row] = {kind = .Setting, label = label, value = value, numeric = numeric}
}

@(private)
change_display :: proc(menu: ^Menu_State, settings: ^Settings, direction: int) {
	if menu.displays.count <= 1 {
		settings.window.display = 0
		return
	}
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
	if info.mode_count == 0 {
		return
	}
	// A desktop-sized borderless window has no smaller alternatives, so choosing
	// a size always starts a window.
	if settings.window.mode == .Borderless {
		settings.window.mode = .Windowed
		settings.window.resolution = display.cycle_mode(info, info.desktop, direction)
		return
	}
	settings.window.resolution = display.cycle_mode(info, settings.window.resolution, direction)
}
