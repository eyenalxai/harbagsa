#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import "core:mem"

import b3 "libs:box3d"

// One placed object as history stores it: the transform stays exact and the id
// survives a restore, so the harness and the inspector never see a new object
// appear where the old one was. Rotation is a quaternion, not a yaw, because a
// yaw round trip through the Box3D trigonometric approximation drifts.
Object_Record :: struct {
	id:          Object_Id,
	name:        [OBJECT_NAME_BYTES]u8,
	name_length: u8,
	prefab:      Prefab_Id,
	body_mode:   Body_Mode,
	center:      b3.Vec3,
	rotation:    b3.Quat,
	color:       [4]f32,
	light:       Light_Settings,
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
			id          = object.id,
			name        = object.name,
			name_length = object.name_length,
			prefab      = object.prefab,
			body_mode   = object.body_mode,
			center      = b3.Body_GetPosition(object.body),
			rotation    = b3.Body_GetRotation(object.body),
			color       = object.color,
			light       = object.light,
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
	clear(&sim.objects)

	next_id := snapshot.next_object_id
	for record in snapshot.objects {
		name_buffer := record.name
		spawn := Object_Spawn {
			name      = string(name_buffer[:record.name_length]),
			prefab    = record.prefab,
			body_mode = record.body_mode,
			center    = record.center,
			light     = record.light,
		}
		if !spawn_object(sim, record.id, spawn, record.rotation, record.color, record.light, true) {
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
	light: Light_Settings,
	settled: bool,
) -> Object_Id {
	return create_object_rotated(
		sim,
		spawn,
		object_rotation(spawn.prefab, spawn.yaw_rad),
		color,
		light,
		settled,
	)
}

// Duplicate and restore paths that already hold an exact quaternion use this so
// they do not round the rotation through yaw again.
@(private)
create_object_rotated :: proc(
	sim: ^Simulation,
	spawn: Object_Spawn,
	rotation: b3.Quat,
	color: [4]f32,
	light: Light_Settings,
	settled: bool,
) -> Object_Id {
	id := sim.next_object_id
	if !spawn_object(sim, id, spawn, rotation, color, light, settled) {
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
	light: Light_Settings,
	settled: bool,
) -> bool {
	if !object_name_valid(spawn.name) || object_name_taken(sim, spawn.name) {
		return false
	}
	box_color := color
	if light.active {
		box_color = light_color4(light.color)
	}
	info := prefab(spawn.prefab)
	body_mode := spawn.body_mode
	body := create_box_body(
		sim.world_id,
		body_type(body_mode),
		spawn.center,
		rotation,
		info.half_extents,
		info.density,
	)
	if !b3.Body_IsValid(body) {
		return false
	}

	object := Placed_Object {
		id          = id,
		name_length = u8(len(spawn.name)),
		prefab      = spawn.prefab,
		body_mode   = body_mode,
		body        = body,
		color       = box_color,
		light       = light,
		spawn_time  = sim.time,
		settled     = settled,
	}
	copy(object.name[:], spawn.name)
	append(&sim.objects, object)
	return true
}
