#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls the menu reset and selection API
package game

import "core:fmt"

MENU_ITEM_COUNT :: 4

MENU_TITLE :: "Settings"
MENU_NOTE :: "Up/Down select    Left/Right change    Enter apply    Esc close"

MENU_ITEM_NAMES := [MENU_ITEM_COUNT]string {
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
	Sprint,
	Crouch,
	Prone,
	Resume,
}

Menu_State :: struct {
	open:     bool,
	selected: Menu_Item,
	text:     Line_Buffer,
}

menu_open :: proc(menu: ^Menu_State) {
	menu.open = true
}

menu_close :: proc(menu: ^Menu_State) {
	menu.open = false
	menu.text.count = 0
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

menu_toggle_setting :: proc(menu: ^Menu_State, settings: ^Settings) -> bool {
	if !menu.open || menu.selected == .Resume {
		return false
	}
	mode := menu_mode(settings^, menu.selected)
	menu_set_mode(settings, menu.selected, toggle_input_mode(mode))
	return true
}

menu_activate :: proc(menu: ^Menu_State, settings: ^Settings) -> bool {
	if !menu.open {
		return false
	}
	if menu_toggle_setting(menu, settings) {
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

	menu.text.lines[0] = fmt.bprintf(
		menu.text.storage[0][:],
		"%-12s %s",
		MENU_ITEM_NAMES[0],
		input_mode_name(settings.sprint_mode),
	)
	menu.text.lines[1] = fmt.bprintf(
		menu.text.storage[1][:],
		"%-12s %s",
		MENU_ITEM_NAMES[1],
		input_mode_name(settings.crouch_mode),
	)
	menu.text.lines[2] = fmt.bprintf(
		menu.text.storage[2][:],
		"%-12s %s",
		MENU_ITEM_NAMES[2],
		input_mode_name(settings.prone_mode),
	)
	menu.text.lines[3] = MENU_ITEM_NAMES[3]
	menu.text.lines[4] = ""
	menu.text.lines[5] = "Controls"

	controls := MENU_CONTROL_LINES[:]
	if debug_active {
		controls = MENU_DEBUG_CONTROL_LINES[:]
	}
	for line, index in controls {
		menu.text.lines[6 + index] = line
	}
	menu.text.count = 6 + len(controls)
}

@(private)
menu_mode :: proc(settings: Settings, item: Menu_Item) -> Input_Mode {
	switch item {
	case .Sprint:
		return settings.sprint_mode
	case .Crouch:
		return settings.crouch_mode
	case .Prone:
		return settings.prone_mode
	case .Resume:
		return .Hold
	}
	return .Hold
}

@(private)
menu_set_mode :: proc(settings: ^Settings, item: Menu_Item, mode: Input_Mode) {
	switch item {
	case .Sprint:
		settings.sprint_mode = mode
	case .Crouch:
		settings.crouch_mode = mode
	case .Prone:
		settings.prone_mode = mode
	case .Resume:
	}
}
