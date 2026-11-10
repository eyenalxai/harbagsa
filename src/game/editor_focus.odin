#+vet explicit-allocators
package game

// The editing half of one frame's ownership. The menu and the platform pointer
// state sit beside it; the cursor sync derives the capture from pointer_free.
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
