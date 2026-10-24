#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:mem"

import b3 "libs:box3d"

// One placed object as history stores it: the transform stays exact and the id
// survives a restore, so the harness and the inspector never see a new object
// appear where the old one was. Rotation is a quaternion, not a yaw, because a
// yaw round trip through the Box3D trigonometric approximation drifts.
Object_Record :: struct {
	id:        Object_Id,
	prefab:    Prefab_Id,
	body_mode: Body_Mode,
	center:    b3.Vec3,
	rotation:  b3.Quat,
	color:     [4]f32,
}

Object_Snapshot :: struct {
	objects:        []Object_Record,
	next_object_id: Object_Id,
}

object_snapshot_capture :: proc(sim: ^Simulation, allocator: mem.Allocator) -> Object_Snapshot {
	count := simulation_object_count(sim)
	snapshot := Object_Snapshot {
		next_object_id = sim.next_object_id,
	}
	if count == 0 {
		return snapshot
	}
	snapshot.objects = make([]Object_Record, count, allocator)
	for object, index in simulation_objects(sim) {
		snapshot.objects[index] = {
			id        = object.id,
			prefab    = object.prefab,
			body_mode = object.body_mode,
			center    = b3.Body_GetPosition(object.body),
			rotation  = b3.Body_GetRotation(object.body),
			color     = object.color,
		}
	}
	return snapshot
}

object_snapshot_destroy :: proc(snapshot: ^Object_Snapshot, allocator: mem.Allocator) {
	if snapshot.objects != nil {
		delete(snapshot.objects, allocator)
	}
	snapshot^ = {}
}

// The snapshot restore path. Every restored object is settled, so undo and redo
// never play the spawn pop. Ids come from the snapshot; the next id only grows,
// so a later placement cannot reuse an id that an undo brought back.
simulation_apply_snapshot :: proc(sim: ^Simulation, snapshot: Object_Snapshot) -> bool {
	if !simulation_is_valid(sim) {
		return false
	}
	for object in simulation_objects(sim) {
		if b3.Body_IsValid(object.body) {
			b3.DestroyBody(object.body)
		}
	}
	sim.objects = {}
	sim.object_count = 0

	next_id := snapshot.next_object_id
	for record in snapshot.objects {
		spawn := Object_Spawn {
			prefab    = record.prefab,
			body_mode = record.body_mode,
			center    = record.center,
		}
		if !spawn_object(sim, record.id, spawn, record.rotation, record.color, true) {
			return false
		}
		next_id = max(next_id, record.id + 1)
	}
	sim.next_object_id = max(sim.next_object_id, next_id)
	return true
}

@(private)
create_object :: proc(
	sim: ^Simulation,
	spawn: Object_Spawn,
	color: [4]f32,
	settled: bool,
) -> Object_Id {
	return create_object_rotated(sim, spawn, object_rotation(spawn.prefab, spawn.yaw), color, settled)
}

// Duplicate and restore paths that already hold an exact quaternion use this so
// they do not round the rotation through yaw again.
@(private)
create_object_rotated :: proc(
	sim: ^Simulation,
	spawn: Object_Spawn,
	rotation: b3.Quat,
	color: [4]f32,
	settled: bool,
) -> Object_Id {
	if sim.object_count >= MAX_PLACED_OBJECTS {
		return INVALID_OBJECT_ID
	}
	id := sim.next_object_id
	if !spawn_object(sim, id, spawn, rotation, color, settled) {
		return INVALID_OBJECT_ID
	}
	sim.next_object_id = id + 1
	return id
}

@(private)
spawn_object :: proc(
	sim: ^Simulation,
	id: Object_Id,
	spawn: Object_Spawn,
	rotation: b3.Quat,
	color: [4]f32,
	settled: bool,
) -> bool {
	if sim.object_count >= MAX_PLACED_OBJECTS {
		return false
	}
	info := prefab(spawn.prefab)
	body := create_box_body(
		sim.world_id,
		body_type(spawn.body_mode),
		spawn.center,
		rotation,
		info.half_extents,
		info.density,
	)
	if !b3.Body_IsValid(body) {
		return false
	}

	sim.objects[sim.object_count] = {
		id         = id,
		prefab     = spawn.prefab,
		body_mode  = spawn.body_mode,
		body       = body,
		color      = color,
		spawn_time = sim.time,
		settled    = settled,
	}
	sim.object_count += 1
	return true
}
