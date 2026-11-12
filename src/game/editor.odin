#+vet explicit-allocators
package game

import "core:mem"

import b3 "libs:box3d"

// The placement settings survive a cancel, so the next arm starts where the last
// placement stopped.
Placement_Defaults :: struct {
	height:      f32,
	yaw_degrees: f32,
	snap:        bool,
}

// The editor owns the debug editing state. Debug mode owns the active flag, the
// camera, and the saved player, so this value survives a mode toggle.
Editor :: struct {
	tool:               Tool,
	selection:          Selection,
	drag:               Drag,
	placement_defaults: Placement_Defaults,
	history:            ^Object_History,
	history_allocator:  mem.Allocator,
}

Selection_None :: struct {}

Selection_Object :: struct {
	id: Object_Id,
}

Selection :: union #no_nil {
	Selection_None,
	Selection_Object,
}

Drag_None :: struct {}

Drag_Active :: struct {
	recorded: bool,
	position: b3.Vec3,
}

// The drag is idle or active as one value, so a position can never outlive the
// drag that owned it.
Drag :: union #no_nil {
	Drag_None,
	Drag_Active,
}

editor_create :: proc(allocator: mem.Allocator) -> Editor {
	return {history_allocator = allocator}
}

editor_destroy :: proc(editor: ^Editor) {
	if editor.history != nil {
		allocator := editor.history.allocator
		object_history_destroy(editor.history)
		free(editor.history, allocator)
		editor.history = nil
	}
	editor^ = {}
}

// The history lives on the heap. It is allocated on the first edit, so a fresh
// editor and a fresh Session stay small.
@(private)
editor_history :: proc(editor: ^Editor) -> ^Object_History {
	if editor.history == nil {
		editor.history = new(Object_History, editor.history_allocator)
		editor.history^ = object_history_create(editor.history_allocator)
	}
	return editor.history
}

@(private)
editor_history_depth :: proc(editor: ^Editor) -> int {
	if editor.history == nil {
		return 0
	}
	return object_history_depth(editor.history)
}

@(private)
editor_history_redo_depth :: proc(editor: ^Editor) -> int {
	if editor.history == nil {
		return 0
	}
	return object_history_redo_depth(editor.history)
}

// A scene replacement is outside the undo history; undo must not restore an
// input from before the replacement.
editor_reset :: proc(editor: ^Editor) {
	if editor.history != nil {
		object_history_clear(editor.history)
	}
	editor_clear_selection(editor)
}

editor_cancel_editing :: proc(editor: ^Editor) {
	editor_end_drag(editor)
	editor_tool_cancel(editor)
}

editor_end_drag :: proc(editor: ^Editor) {
	editor.drag = Drag_None{}
}

@(private)
editor_dragging :: proc(editor: ^Editor) -> bool {
	_, dragging := editor.drag.(Drag_Active)
	return dragging
}

editor_clear_selection :: proc(editor: ^Editor) {
	editor_end_drag(editor)
	editor.selection = Selection_None{}
}

editor_repair_selection :: proc(editor: ^Editor, sim: ^Simulation) {
	if _, is_object := editor.selection.(Selection_Object); !is_object {
		return
	}
	if _, live := editor_selected_object_id(editor, sim); !live {
		editor_clear_selection(editor)
	}
}

editor_selected_object_id :: proc(editor: ^Editor, sim: ^Simulation) -> (Object_Id, bool) {
	selected, is_object := editor.selection.(Selection_Object)
	if !is_object {
		return INVALID_OBJECT_ID, false
	}
	if _, found := simulation_object_find(sim, selected.id); !found {
		return INVALID_OBJECT_ID, false
	}
	return selected.id, true
}

@(private)
editor_selected_object :: proc(editor: ^Editor, sim: ^Simulation) -> (Placed_Object, bool) {
	id, ok := editor_selected_object_id(editor, sim)
	if !ok {
		return {}, false
	}
	return simulation_object_find(sim, id)
}

@(private)
editor_selection_set :: proc(editor: ^Editor, id: Object_Id) {
	editor_end_drag(editor)
	editor.selection = Selection_Object{id = id}
}
