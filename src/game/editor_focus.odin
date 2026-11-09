#+vet explicit-allocators
#+vet !unused-procedures // the window loop reads this; the game binary does not
package game

// The editing half of one frame's ownership. The menu and the platform pointer
// state sit beside it; the cursor owner reads pointer_free instead of caching a
// palette latch.
Editor_Focus :: struct {
	active:       bool,
	tool:         Editor_Tool,
	dragging:     bool,
	pointer_free: bool,
}

editor_focus :: proc(editor: ^Editor, active: bool) -> Editor_Focus {
	tool := editor_tool_kind(editor.tool)
	return {
		active = active,
		tool = tool,
		dragging = editor.dragging,
		pointer_free = tool == .Palette,
	}
}

// Focus is the game half of one frame's input state. The input module owns the
// platform half (captured, pointer_available); this value says which part of
// the game owns the frame.
Focus :: struct {
	menu_open: bool,
	editor:    Editor_Focus,
}

focus :: proc(dm: ^Debug_Mode, menu: ^Menu_State) -> Focus {
	return {
		menu_open = menu.open,
		editor = editor_focus(&dm.editor, dm.active),
	}
}
