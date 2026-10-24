#+vet explicit-allocators
package game

import "src:ui"

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
	{},
	{},
	{},
	{},
}

MENU_DEBUG_CONTROL_HINTS := [MENU_HINT_COUNT]ui.Hint_Cell {
	{keys = "WASD", action = "fly"},
	{keys = "Space/Ctrl", action = "up / down"},
	{keys = "Click", action = "select or place"},
	{keys = "Drag", action = "move"},
	{keys = "Wheel", action = "height"},
	{keys = "Tab", action = "palette"},
	{keys = "Q/E", action = "rotate"},
	{keys = "G", action = "snap"},
	{keys = "M", action = "body"},
	{keys = "Delete or X", action = "remove"},
	{keys = "L", action = "sun place"},
	{keys = "R", action = "reset player"},
	{keys = "Shift+R", action = "scene"},
	{keys = "F1", action = "debug view"},
	{keys = "F2", action = "exit"},
	{keys = "F3", action = "TAA"},
	{keys = "F4", action = "perf"},
	{keys = "Esc", action = "settings"},
	{keys = "Ctrl+D", action = "duplicate"},
	{keys = "Ctrl+Z", action = "undo"},
	{keys = "Ctrl+Shift+Z", action = "redo"},
	{keys = "C [ ] , .", action = "lamp light"},
}
