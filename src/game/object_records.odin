#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import "core:fmt"
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

Placed_Object_Build :: struct {
	id:       Object_Id,
	spawn:    Object_Spawn,
	rotation: b3.Quat,
	color:    [4]f32,
	light:    Light_Settings,
	settled:  bool,
}

Snapshot_Apply_Error :: enum {
	None,
	Invalid_Simulation,
	Invalid_Id,
	Duplicate_Id,
	Invalid_Name,
	Duplicate_Name,
	Body,
}

Snapshot_Apply_Failure :: struct {
	error:        Snapshot_Apply_Error,
	offending_id: Object_Id,
}

snapshot_apply_error_message :: proc(failure: Snapshot_Apply_Failure) -> string {
	switch failure.error {
	case .None:
		return ""
	case .Invalid_Simulation:
		return "the simulation is not valid"
	case .Invalid_Id:
		return fmt.tprintf("object id %d is not valid", failure.offending_id)
	case .Duplicate_Id:
		return fmt.tprintf("object id %d is given twice", failure.offending_id)
	case .Invalid_Name:
		return "the snapshot has an invalid object name"
	case .Duplicate_Name:
		return "the snapshot has a duplicate object name"
	case .Body:
		return "the snapshot could not create a body"
	}
	return "the snapshot could not be applied"
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
// so a later placement cannot reuse an id that an undo brought back. The whole
// replacement set is built before the live bodies are destroyed, so a failure
// leaves the old scene intact.
simulation_apply_snapshot :: proc(
	sim: ^Simulation,
	snapshot: Object_Snapshot,
) -> Snapshot_Apply_Failure {
	if !simulation_is_valid(sim) {
		return {error = .Invalid_Simulation}
	}
	for record, index in snapshot.objects {
		if record.id == INVALID_OBJECT_ID {
			return {error = .Invalid_Id, offending_id = record.id}
		}
		for previous in snapshot.objects[:index] {
			if previous.id == record.id {
				return {error = .Duplicate_Id, offending_id = record.id}
			}
		}
	}
	objects := make([dynamic]Placed_Object, 0, len(snapshot.objects), sim.allocator)
	next_id := snapshot.next_object_id
	for &record in snapshot.objects {
		name := string(record.name[:record.name_length])
		if !object_name_valid(name) {
			destroy_placed_objects(objects)
			return {error = .Invalid_Name}
		}
		if object_list_name_taken(objects[:], name) {
			destroy_placed_objects(objects)
			return {error = .Duplicate_Name}
		}
		spawn := Object_Spawn {
			name      = name,
			prefab    = record.prefab,
			body_mode = record.body_mode,
			center    = record.center,
			light     = record.light,
		}
		object, ok := make_placed_object(
			sim,
			{
				id = record.id,
				spawn = spawn,
				rotation = record.rotation,
				color = record.color,
				light = record.light,
				settled = true,
			},
		)
		if !ok {
			destroy_placed_objects(objects)
			return {error = .Body}
		}
		append(&objects, object)
		next_id = max(next_id, record.id + 1)
	}

	for object in simulation_objects(sim) {
		if b3.Body_IsValid(object.body) {
			b3.DestroyBody(object.body)
		}
	}
	delete(sim.objects)
	sim.objects = objects
	sim.next_object_id = max(sim.next_object_id, next_id)
	return {}
}

@(private)
create_object :: proc(
	sim: ^Simulation,
	spawn: Object_Spawn,
	color: [4]f32,
	light: Light_Settings,
	settled: bool,
) -> Object_Id {
	return create_object_build(
		sim,
		{
			spawn = spawn,
			rotation = object_rotation(spawn.prefab, spawn.yaw_rad),
			color = color,
			light = light,
			settled = settled,
		},
	)
}

// Duplicate and restore paths that already hold an exact quaternion use this so
// they do not round the rotation through yaw again.
@(private)
create_object_build :: proc(sim: ^Simulation, build: Placed_Object_Build) -> Object_Id {
	spec := build
	spec.id = sim.next_object_id
	if !spawn_object(sim, spec) {
		return INVALID_OBJECT_ID
	}
	sim.next_object_id = spec.id + 1
	return spec.id
}

@(private)
spawn_object :: proc(sim: ^Simulation, build: Placed_Object_Build) -> bool {
	if !object_name_valid(build.spawn.name) || object_name_taken(sim, build.spawn.name) {
		return false
	}
	object, ok := make_placed_object(sim, build)
	if !ok {
		return false
	}
	append(&sim.objects, object)
	return true
}

@(private)
make_placed_object :: proc(sim: ^Simulation, build: Placed_Object_Build) -> (Placed_Object, bool) {
	box_color := build.color
	if build.light.active {
		box_color = light_color4(build.light.color)
	}
	info := prefab(build.spawn.prefab)
	body_mode := build.spawn.body_mode
	if build.light.active {
		body_mode = lamp_kind_body(build.light.kind)
	}
	body := create_box_body(
		sim.world_id,
		body_type(body_mode),
		build.spawn.center,
		build.rotation,
		info.half_extents,
		info.density,
	)
	if !b3.Body_IsValid(body) {
		return {}, false
	}

	object := Placed_Object {
		id          = build.id,
		name_length = u8(len(build.spawn.name)),
		prefab      = build.spawn.prefab,
		body_mode   = body_mode,
		body        = body,
		color       = box_color,
		light       = build.light,
		spawn_time  = sim.time,
		settled     = build.settled,
	}
	copy(object.name[:], build.spawn.name)
	return object, true
}

@(private)
destroy_placed_objects :: proc(objects: [dynamic]Placed_Object) {
	for object in objects {
		if b3.Body_IsValid(object.body) {
			b3.DestroyBody(object.body)
		}
	}
	delete(objects)
}
