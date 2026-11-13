#+vet explicit-allocators
package game

import "src:ui"

MENU_CONTROL_HINTS := [MENU_HINT_COUNT]ui.Hint_Cell {
	{keys = "WASD", action = "move"},
	{keys = "Mouse", action = "look"},
	{keys = "Space", action = "jump"},
	{keys = "Shift", action = "sprint"},
	{keys = "Esc", action = "settings"},
	{keys = "F2", action = "debug mode"},
}

MENU_DEBUG_CONTROL_HINTS := [MENU_HINT_COUNT]ui.Hint_Cell {
	{keys = "WASD", action = "fly"},
	{keys = "Click", action = "select"},
	{keys = "Tab", action = "palette"},
	{keys = "G", action = "snap"},
	{keys = "Delete", action = "remove"},
	{keys = "Esc", action = "settings"},
}
