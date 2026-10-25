#+vet explicit-allocators
#+vet !unused-procedures // the window loop and tests read this; the game binary does not
package game

// Focus is the game half of one frame's input state. The input module owns the
// platform half (captured, pointer_available); this value says which part of
// the game owns the frame.
Focus :: struct {
	menu_open:    bool,
	debug_active: bool,
	tool:         Active_Tool,
	dragging:     bool,
}

focus :: proc(dm: ^Debug_Mode, menu: ^Menu_State) -> Focus {
	return {
		menu_open = menu.open,
		debug_active = dm.active,
		tool = active_tool(dm),
		dragging = dm.dragging == .Object,
	}
}
