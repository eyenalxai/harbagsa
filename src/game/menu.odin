#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls the menu reset and selection API
package game

import "core:fmt"

import "src:display"

MENU_ITEM_COUNT :: 7

MENU_TITLE :: "Settings"
MENU_NOTE :: "Up/Down select    Left/Right change    Enter change    Esc close"

MENU_ITEM_NAMES := [MENU_ITEM_COUNT]string {
	"Window mode",
	"Display",
	"Resolution",
	"Sprint mode",
	"Crouch mode",
	"Prone mode",
	"Resume",
}

MENU_CONTROL_LINES := [5]string {
	"WASD move    Mouse look    Left click capture",
	"Shift sprint    Space jump or hold to mantle",
	"C crouch or slide    Z prone, crawl, or dive",
	"R reset    Shift+R scene    F1 debug view",
	"F2 debug mode    F3 TAA    Esc settings",
}

MENU_DEBUG_CONTROL_LINES := [5]string {
	"WASD fly    Space up    Ctrl down",
	"Click select    Drag move    Wheel height",
	"E add    Delete or X remove    L sun",
	"R reset player    F2 exit    Shift+R scene",
	"F1 debug view    F3 TAA    Esc settings",
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
	text:     Line_Buffer,
	displays: display.List,
}

menu_open :: proc(menu: ^Menu_State) {
	menu.open = true
}

menu_close :: proc(menu: ^Menu_State) {
	menu.open = false
	menu.text.count = 0
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

menu_activate :: proc(menu: ^Menu_State, settings: ^Settings) -> bool {
	if !menu.open {
		return false
	}
	if menu_change_setting(menu, settings, 1) {
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
		menu.text.count = 0
		return
	}

	resolution := settings_effective_resolution(settings, &menu.displays)
	menu.text.lines[0] = fmt.bprintf(
		menu.text.storage[0][:],
		"%-12s %s",
		MENU_ITEM_NAMES[0],
		window_mode_name(settings.window.mode),
	)
	menu.text.lines[1] = fmt.bprintf(
		menu.text.storage[1][:],
		"%-12s %s",
		MENU_ITEM_NAMES[1],
		settings_display_name(settings, &menu.displays),
	)
	menu.text.lines[2] = fmt.bprintf(
		menu.text.storage[2][:],
		"%-12s %dx%d",
		MENU_ITEM_NAMES[2],
		resolution.width,
		resolution.height,
	)
	menu.text.lines[3] = fmt.bprintf(
		menu.text.storage[3][:],
		"%-12s %s",
		MENU_ITEM_NAMES[3],
		input_mode_name(settings.sprint_mode),
	)
	menu.text.lines[4] = fmt.bprintf(
		menu.text.storage[4][:],
		"%-12s %s",
		MENU_ITEM_NAMES[4],
		input_mode_name(settings.crouch_mode),
	)
	menu.text.lines[5] = fmt.bprintf(
		menu.text.storage[5][:],
		"%-12s %s",
		MENU_ITEM_NAMES[5],
		input_mode_name(settings.prone_mode),
	)
	menu.text.lines[6] = MENU_ITEM_NAMES[6]
	menu.text.lines[7] = ""
	menu.text.lines[8] = "Controls"

	controls := MENU_CONTROL_LINES[:]
	if debug_active {
		controls = MENU_DEBUG_CONTROL_LINES[:]
	}
	for line, index in controls {
		menu.text.lines[9 + index] = line
	}
	menu.text.count = 9 + len(controls)
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
