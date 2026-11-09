#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import "core:math"
import "core:mem"

import b3 "libs:box3d"

HISTORY_LIMIT :: 64

// The history keeps snapshots on the heap. Debug_Mode carries a pointer to this
// header and the allocator, so 64 full scenes never sit inline in the debug
// state or in the harness Session.
Object_History :: struct {
	allocator: mem.Allocator,
	undo:      [dynamic]Object_Snapshot,
	redo:      [dynamic]Object_Snapshot,
}

History_Result :: struct {
	applied: bool,
	id:      Object_Id,
}

History_Mutation :: union #no_nil {
	History_Move,
	History_Rotate,
	History_Convert,
	History_Delete,
	History_Duplicate,
	History_Light,
	History_Place,
}

History_Move :: struct {
	id:     Object_Id,
	center: b3.Vec3,
}

History_Rotate :: struct {
	id:      Object_Id,
	degrees: f32,
}

History_Convert :: struct {
	id:   Object_Id,
	mode: Body_Mode,
}

History_Delete :: struct {
	id: Object_Id,
}

History_Duplicate :: struct {
	id: Object_Id,
}

History_Light :: struct {
	id:       Object_Id,
	settings: Light_Settings,
	next:     Light_Settings,
}

History_Place :: struct {
	spawn: Object_Spawn,
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

// The only path that adds an undo entry: capture, mutate, commit. A failed
// mutation destroys the snapshot, so both stacks and the redo entries survive.
object_history_apply :: proc(
	history: ^Object_History,
	sim: ^Simulation,
	mutation: History_Mutation,
) -> History_Result {
	snapshot := object_snapshot_capture(sim, history.allocator)
	applied, id := history_mutation_apply(sim, mutation)
	if !applied {
		object_snapshot_destroy(&snapshot, history.allocator)
		return {}
	}

	if history.undo == nil {
		history.undo = make([dynamic]Object_Snapshot, 0, HISTORY_LIMIT, history.allocator)
	}
	if len(history.undo) >= HISTORY_LIMIT {
		object_snapshot_destroy(&history.undo[0], history.allocator)
		ordered_remove(&history.undo, 0)
	}
	append(&history.undo, snapshot)
	object_history_clear_redo(history)
	return {applied = true, id = id}
}

@(private)
history_mutation_apply :: proc(
	sim: ^Simulation,
	mutation: History_Mutation,
) -> (
	applied: bool,
	id: Object_Id,
) {
	switch value in mutation {
	case History_Move:
		return simulation_move_object(sim, value.id, value.center), value.id
	case History_Rotate:
		yaw := simulation_object_yaw(sim, value.id) + value.degrees * math.PI / 180.0
		return simulation_set_object_yaw(sim, value.id, yaw), value.id
	case History_Convert:
		return simulation_convert_object(sim, value.id, value.mode), value.id
	case History_Delete:
		return simulation_remove_object(sim, value.id), value.id
	case History_Duplicate:
		object, ok := simulation_object_find(sim, value.id)
		if !ok {
			return false, INVALID_OBJECT_ID
		}
		spawn := Object_Spawn {
			prefab    = object.prefab,
			body_mode = object.body_mode,
			center    = b3.Body_GetPosition(object.body) + {prefab(object.prefab).half_extents.x, 0.0, 0.0},
			light     = object.light,
		}
		created := create_object_rotated(
			sim,
			spawn,
			b3.Body_GetRotation(object.body),
			object.color,
			object.light,
			false,
		)
		return created != INVALID_OBJECT_ID, created
	case History_Light:
		if value.next.kind != value.settings.kind {
			return simulation_set_lamp_kind(sim, value.id, value.next.kind), value.id
		}
		return simulation_set_object_light(sim, value.id, value.next), value.id
	case History_Place:
		created := simulation_create_object(sim, value.spawn)
		return created != INVALID_OBJECT_ID, created
	}
	return false, INVALID_OBJECT_ID
}

object_history_undo :: proc(history: ^Object_History, sim: ^Simulation) -> Edit_Result {
	if len(history.undo) == 0 {
		return edit_fail(.Nothing_To_Undo)
	}
	if history.redo == nil {
		history.redo = make([dynamic]Object_Snapshot, 0, HISTORY_LIMIT, history.allocator)
	}
	index := len(history.undo) - 1
	restore := history.undo[index]
	redo := object_snapshot_capture(sim, history.allocator)
	if !simulation_apply_snapshot(sim, restore) {
		object_snapshot_destroy(&redo, history.allocator)
		return edit_fail(.Failed)
	}
	object_snapshot_destroy(&history.undo[index], history.allocator)
	ordered_remove(&history.undo, index)
	append(&history.redo, redo)
	return edit_ok()
}

object_history_redo :: proc(history: ^Object_History, sim: ^Simulation) -> Edit_Result {
	if len(history.redo) == 0 {
		return edit_fail(.Nothing_To_Redo)
	}
	if history.undo == nil {
		history.undo = make([dynamic]Object_Snapshot, 0, HISTORY_LIMIT, history.allocator)
	}
	index := len(history.redo) - 1
	restore := history.redo[index]
	undo := object_snapshot_capture(sim, history.allocator)
	if !simulation_apply_snapshot(sim, restore) {
		object_snapshot_destroy(&undo, history.allocator)
		return edit_fail(.Failed)
	}
	object_snapshot_destroy(&history.redo[index], history.allocator)
	ordered_remove(&history.redo, index)
	append(&history.undo, undo)
	return edit_ok()
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
