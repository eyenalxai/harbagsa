#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:mem"

HISTORY_LIMIT :: 64

// The history keeps snapshots on the heap. Debug_Mode carries a pointer to this
// header and the allocator, so 64 full scenes never sit inline in the debug
// state or in the harness Session.
Object_History :: struct {
	allocator: mem.Allocator,
	undo:      [dynamic]Object_Snapshot,
	redo:      [dynamic]Object_Snapshot,
}

object_history_create :: proc(allocator: mem.Allocator) -> Object_History {
	return {allocator = allocator}
}

object_history_destroy :: proc(history: ^Object_History) {
	object_history_clear(history)
	if history.undo != nil {
		delete(history.undo)
	}
	if history.redo != nil {
		delete(history.redo)
	}
	history^ = {}
}

object_history_clear :: proc(history: ^Object_History) {
	object_history_clear_redo(history)
	for &snapshot in history.undo {
		object_snapshot_destroy(&snapshot, history.allocator)
	}
	if history.undo != nil {
		clear(&history.undo)
	}
}

object_history_depth :: proc(history: ^Object_History) -> int {
	return len(history.undo)
}

object_history_redo_depth :: proc(history: ^Object_History) -> int {
	return len(history.redo)
}

object_history_record :: proc(history: ^Object_History, sim: ^Simulation) {
	object_history_push(history, object_snapshot_capture(sim, history.allocator))
}

// The caller captures the snapshot before the mutation and pushes it only when
// the mutation succeeds, so a failed edit cannot leave a duplicate entry.
object_history_push :: proc(history: ^Object_History, snapshot: Object_Snapshot) {
	if history.undo == nil {
		history.undo = make([dynamic]Object_Snapshot, 0, HISTORY_LIMIT, history.allocator)
	}
	if len(history.undo) >= HISTORY_LIMIT {
		object_snapshot_destroy(&history.undo[0], history.allocator)
		ordered_remove(&history.undo, 0)
	}
	append(&history.undo, snapshot)
	object_history_clear_redo(history)
}

object_history_undo :: proc(history: ^Object_History, sim: ^Simulation) -> bool {
	if len(history.undo) == 0 {
		return false
	}
	if history.redo == nil {
		history.redo = make([dynamic]Object_Snapshot, 0, HISTORY_LIMIT, history.allocator)
	}
	index := len(history.undo) - 1
	snapshot := history.undo[index]
	ordered_remove(&history.undo, index)
	append(&history.redo, object_snapshot_capture(sim, history.allocator))
	applied := simulation_apply_snapshot(sim, snapshot)
	object_snapshot_destroy(&snapshot, history.allocator)
	return applied
}

object_history_redo :: proc(history: ^Object_History, sim: ^Simulation) -> bool {
	if len(history.redo) == 0 {
		return false
	}
	index := len(history.redo) - 1
	snapshot := history.redo[index]
	ordered_remove(&history.redo, index)
	append(&history.undo, object_snapshot_capture(sim, history.allocator))
	applied := simulation_apply_snapshot(sim, snapshot)
	object_snapshot_destroy(&snapshot, history.allocator)
	return applied
}

@(private)
object_history_clear_redo :: proc(history: ^Object_History) {
	for &snapshot in history.redo {
		object_snapshot_destroy(&snapshot, history.allocator)
	}
	if history.redo != nil {
		clear(&history.redo)
	}
}
