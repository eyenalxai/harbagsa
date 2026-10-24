#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:math"

import b3 "libs:box3d"
import "src:geometry"

Object_Id :: u32

INVALID_OBJECT_ID :: Object_Id(0)

Placed_Object :: struct {
	id:         Object_Id,
	prefab:     Prefab_Id,
	body_mode:  Body_Mode,
	body:       b3.BodyId,
	color:      [4]f32,
	spawn_time: f32,
}

Object_Spawn :: struct {
	prefab:    Prefab_Id,
	body_mode: Body_Mode,
	center:    b3.Vec3,
	yaw:       f32,
}

// Read-only view for iteration. Every mutation takes an Object_Id.
simulation_objects :: proc(sim: ^Simulation) -> []Placed_Object {
	return sim.objects[:sim.object_count]
}

simulation_object_count :: proc(sim: ^Simulation) -> int {
	return sim.object_count
}

simulation_object_find :: proc(sim: ^Simulation, id: Object_Id) -> (Placed_Object, bool) {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return {}, false
	}
	return sim.objects[index], true
}

simulation_object_body :: proc(sim: ^Simulation, id: Object_Id) -> b3.BodyId {
	object, ok := simulation_object_find(sim, id)
	if !ok {
		return {}
	}
	return object.body
}

simulation_object_box :: proc(sim: ^Simulation, id: Object_Id) -> geometry.Box {
	object, ok := simulation_object_find(sim, id)
	if !ok || !b3.Body_IsValid(object.body) {
		return {}
	}
	rotation := b3.Body_GetRotation(object.body)
	info := prefab(object.prefab)
	return {
		center = b3.ToVec3(b3.Body_GetPosition(object.body)),
		half_extents = info.half_extents,
		color = object.color,
		rotation = {rotation.x, rotation.y, rotation.z, rotation.w},
	}
}

simulation_create_object :: proc(sim: ^Simulation, spawn: Object_Spawn) -> Object_Id {
	return create_object(sim, spawn, prefab(spawn.prefab).color)
}

simulation_remove_object :: proc(sim: ^Simulation, id: Object_Id) -> bool {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return false
	}

	b3.DestroyBody(sim.objects[index].body)
	for next in index ..< sim.object_count - 1 {
		sim.objects[next] = sim.objects[next + 1]
	}
	sim.object_count -= 1
	sim.objects[sim.object_count] = {}
	return true
}

simulation_move_object :: proc(sim: ^Simulation, id: Object_Id, center: b3.Vec3) -> bool {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return false
	}
	body := sim.objects[index].body
	if !b3.Body_IsValid(body) {
		return false
	}

	// Body_SetTransform does not wake the body or clear momentum.
	b3.Body_SetTransform(body, center, b3.Body_GetRotation(body))
	stop_body(body)
	return true
}

simulation_object_yaw :: proc(sim: ^Simulation, id: Object_Id) -> f32 {
	object, ok := simulation_object_find(sim, id)
	if !ok || !b3.Body_IsValid(object.body) {
		return 0.0
	}

	rotation := b3.Body_GetRotation(object.body)
	pitch := prefab(object.prefab).base_pitch
	if pitch != 0.0 {
		rotation = b3.MulQuat(rotation, pitch_inverse(pitch))
	}
	return b3.UnwindAngle(2.0 * math.atan2(rotation.y, rotation.w))
}

simulation_set_object_yaw :: proc(sim: ^Simulation, id: Object_Id, yaw: f32) -> bool {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return false
	}
	object := sim.objects[index]
	if !b3.Body_IsValid(object.body) {
		return false
	}

	b3.Body_SetTransform(
		object.body,
		b3.Body_GetPosition(object.body),
		object_rotation(object.prefab, yaw),
	)
	stop_body(object.body)
	return true
}

simulation_convert_object :: proc(sim: ^Simulation, id: Object_Id, mode: Body_Mode) -> bool {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return false
	}
	object := &sim.objects[index]
	if object.body_mode == mode {
		return true
	}
	if !b3.Body_IsValid(object.body) {
		return false
	}

	info := prefab(object.prefab)
	body := create_box_body(
		sim.world_id,
		body_type(mode),
		b3.ToVec3(b3.Body_GetPosition(object.body)),
		b3.Body_GetRotation(object.body),
		info.half_extents,
		info.density,
	)
	if !b3.Body_IsValid(body) {
		return false
	}

	b3.DestroyBody(object.body)
	object.body = body
	object.body_mode = mode
	return true
}

simulation_object_id_for_body :: proc(sim: ^Simulation, body: b3.BodyId) -> Object_Id {
	for object in simulation_objects(sim) {
		if object.body == body {
			return object.id
		}
	}
	return INVALID_OBJECT_ID
}

simulation_reset_objects :: proc(sim: ^Simulation) {
	for object in simulation_objects(sim) {
		if b3.Body_IsValid(object.body) {
			b3.DestroyBody(object.body)
		}
	}
	sim.objects = {}
	sim.object_count = 0
	sim.next_object_id = 1

	colors := INITIAL_CRATE_COLORS
	for position, index in INITIAL_CRATE_POSITIONS {
		_ = create_object(
			sim,
			{
				prefab = .Crate,
				body_mode = .Dynamic,
				center = position,
				yaw = 0.0,
			},
			colors[index],
		)
	}
}

simulation_reset_scene :: proc(sim: ^Simulation) {
	simulation_reset_objects(sim)
	simulation_reset(sim)
}

@(private)
create_object :: proc(sim: ^Simulation, spawn: Object_Spawn, color: [4]f32) -> Object_Id {
	if sim.object_count >= MAX_PLACED_OBJECTS {
		return INVALID_OBJECT_ID
	}
	info := prefab(spawn.prefab)
	body := create_box_body(
		sim.world_id,
		body_type(spawn.body_mode),
		spawn.center,
		object_rotation(spawn.prefab, spawn.yaw),
		info.half_extents,
		info.density,
	)
	if !b3.Body_IsValid(body) {
		return INVALID_OBJECT_ID
	}

	id := sim.next_object_id
	sim.objects[sim.object_count] = {
		id = id,
		prefab = spawn.prefab,
		body_mode = spawn.body_mode,
		body = body,
		color = color,
		// The spawn clock lands with the pop animation; until then every object
		// reports a settled spawn time.
		spawn_time = 0.0,
	}
	sim.object_count += 1
	sim.next_object_id += 1
	return id
}

@(private)
object_index_for_id :: proc(sim: ^Simulation, id: Object_Id) -> (index: int, ok: bool) {
	if id == INVALID_OBJECT_ID {
		return -1, false
	}
	for object, cursor in simulation_objects(sim) {
		if object.id == id {
			return cursor, true
		}
	}
	return -1, false
}

@(private)
object_rotation :: proc(prefab_id: Prefab_Id, yaw: f32) -> b3.Quat {
	rotation := b3.MakeQuatFromAxisAngle({0.0, 1.0, 0.0}, yaw)
	pitch := prefab(prefab_id).base_pitch
	if pitch != 0.0 {
		rotation = b3.MulQuat(rotation, b3.MakeQuatFromAxisAngle({1.0, 0.0, 0.0}, pitch))
	}
	return rotation
}

@(private)
pitch_inverse :: proc(pitch: f32) -> b3.Quat {
	return b3.NegateQuat(b3.MakeQuatFromAxisAngle({1.0, 0.0, 0.0}, pitch))
}

@(private)
body_type :: proc(mode: Body_Mode) -> b3.BodyType {
	return mode == .Static ? .staticBody : .dynamicBody
}

@(private)
stop_body :: proc(body: b3.BodyId) {
	b3.Body_SetLinearVelocity(body, b3.Vec3_zero)
	b3.Body_SetAngularVelocity(body, b3.Vec3_zero)
	b3.Body_SetAwake(body, true)
}
