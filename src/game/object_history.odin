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
	id:            Object_Id,
	previous_kind: Lamp_Kind,
	next:          Light_Settings,
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

// A failed mutation destroys the snapshot, so both stacks and the redo entries
// survive.
object_history_apply :: proc(
	history: ^Object_History,
	sim: ^Simulation,
	mutation: History_Mutation,
) -> (
	Edit_Result,
	Object_Id,
) {
	snapshot := object_snapshot_capture(sim, history.allocator)
	applied, id := history_mutation_apply(sim, mutation)
	if !applied {
		object_snapshot_destroy(&snapshot, history.allocator)
		return edit_fail(.Failed), INVALID_OBJECT_ID
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
	return edit_ok(), id
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
		created := create_object_build(
			sim,
			{
				spawn = spawn,
				rotation = b3.Body_GetRotation(object.body),
				color = object.color,
				light = object.light,
				settled = false,
			},
		)
		return created != INVALID_OBJECT_ID, created
	case History_Light:
		if value.next.kind != value.previous_kind {
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
	return object_history_step(history, sim, &history.undo, &history.redo, .Nothing_To_Undo)
}

object_history_redo :: proc(history: ^Object_History, sim: ^Simulation) -> Edit_Result {
	return object_history_step(history, sim, &history.redo, &history.undo, .Nothing_To_Redo)
}

@(private)
object_history_step :: proc(
	history: ^Object_History,
	sim: ^Simulation,
	from: ^[dynamic]Object_Snapshot,
	to: ^[dynamic]Object_Snapshot,
	empty: Edit_Reason,
) -> Edit_Result {
	if len(from^) == 0 {
		return edit_fail(empty)
	}
	if to^ == nil {
		to^ = make([dynamic]Object_Snapshot, 0, HISTORY_LIMIT, history.allocator)
	}
	index := len(from^) - 1
	restore := from^[index]
	opposite := object_snapshot_capture(sim, history.allocator)
	if apply_error := simulation_apply_snapshot(sim, restore); apply_error != .None {
		object_snapshot_destroy(&opposite, history.allocator)
		return edit_fail(snapshot_restore_reason(apply_error))
	}
	object_snapshot_destroy(&from^[index], history.allocator)
	ordered_remove(from, index)
	append(to, opposite)
	return edit_ok()
}

@(private)
snapshot_restore_reason :: proc(error: Snapshot_Apply_Error) -> Edit_Reason {
	switch error {
	case .None:
		return .None
	case .Invalid_Simulation:
		return .Restore_Invalid_Scene
	case .Invalid_Name:
		return .Restore_Invalid_Name
	case .Duplicate_Name:
		return .Restore_Duplicate_Name
	case .Body:
		return .Restore_Body
	}
	return .Failed
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
