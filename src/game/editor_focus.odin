#+vet explicit-allocators
package game

// The editing half of one frame's ownership. The menu and the platform pointer
// state sit beside it; the frame focus combines them.
Editor_Focus :: struct {
	active:       bool,
	tool:         Tool_Kind,
	dragging:     bool,
	pointer_free: bool,
}

editor_focus :: proc(editor: ^Editor, active: bool) -> Editor_Focus {
	tool := tool_kind(editor.tool)
	return {
		active = active,
		tool = tool,
		dragging = editor_dragging(editor),
		pointer_free = tool == .Palette,
	}
}

// Focus is the game half of one frame's input state. The input module owns the
// platform half (captured, pointer_available); this value says which part of
// the game owns the frame.
Focus :: struct {
	menu_open:   bool,
	editor:      Editor_Focus,
	pointer_free: bool,
}

focus :: proc(dm: ^Debug_Mode, menu: ^Menu_State) -> Focus {
	editor := editor_focus(&dm.editor, dm.active)
	return {
		menu_open = menu.open,
		editor = editor,
		pointer_free = menu.open || editor.pointer_free,
	}
}
