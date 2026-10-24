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
