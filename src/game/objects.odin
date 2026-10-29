#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import "core:math"

import b3 "libs:box3d"
import "src:geometry"

Object_Id :: u32

INVALID_OBJECT_ID :: Object_Id(0)

// A name is a fixed inline buffer: an object record is copied into history,
// scene snapshots, and the query state, so an owned string would need a free on
// every path. The cap is one short scenario handle, not a label.
OBJECT_NAME_BYTES :: 32
OBJECT_NAME_MAX :: OBJECT_NAME_BYTES - 1

Placed_Object :: struct {
	id:         Object_Id,
	name:       [OBJECT_NAME_BYTES]u8,
	name_length: u8,
	prefab:     Prefab_Id,
	body_mode:  Body_Mode,
	body:       b3.BodyId,
	color:      [4]f32,
	light:      Light_Settings,
	spawn_time: f32,
	settled:    bool,
}

Object_Spawn :: struct {
	name:      string,
	prefab:    Prefab_Id,
	body_mode: Body_Mode,
	center:    b3.Vec3,
	yaw_rad:   f32,
	light:     Light_Settings,
}

// Read-only view for iteration. Every mutation takes an Object_Id.
simulation_objects :: proc(sim: ^Simulation) -> []Placed_Object {
	return sim.objects[:]
}

simulation_object_count :: proc(sim: ^Simulation) -> int {
	return len(sim.objects)
}

simulation_object_find :: proc(sim: ^Simulation, id: Object_Id) -> (Placed_Object, bool) {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return {}, false
	}
	return sim.objects[index], true
}

object_name :: proc(object: ^Placed_Object) -> string {
	return string(object.name[:object.name_length])
}

// An empty name is unnamed. A name may not be all digits, because a field path
// reads `objects.<id>` when the handle parses as a number, and it may not be
// `count`, which is the list length.
object_name_valid :: proc(name: string) -> bool {
	if name == "" {
		return true
	}
	if len(name) > OBJECT_NAME_MAX || name == "count" {
		return false
	}
	digits_only := true
	for character in name {
		if character >= '0' && character <= '9' {
			continue
		}
		digits_only = false
		if character >= 'a' && character <= 'z' {
			continue
		}
		if character >= 'A' && character <= 'Z' {
			continue
		}
		if character == '-' || character == '_' {
			continue
		}
		return false
	}
	return !digits_only
}

object_name_taken :: proc(sim: ^Simulation, name: string) -> bool {
	if name == "" {
		return false
	}
	for &object in simulation_objects(sim) {
		if object_name(&object) == name {
			return true
		}
	}
	return false
}

simulation_object_name :: proc(sim: ^Simulation, id: Object_Id) -> string {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return ""
	}
	return object_name(&sim.objects[index])
}

simulation_object_find_by_name :: proc(
	sim: ^Simulation,
	name: string,
) -> (
	Placed_Object,
	bool,
) {
	if name == "" {
		return {}, false
	}
	for &object in simulation_objects(sim) {
		if object_name(&object) == name {
			return object, true
		}
	}
	return {}, false
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
	if !ok {
		return {}
	}
	return object_box(object)
}

// The pop is visual only. The body keeps its full size, so the editor and the
// harness state use this box while the renderer and the outline use
// simulation_object_visual_box.
@(private)
object_box :: proc(object: Placed_Object) -> geometry.Box {
	if !b3.Body_IsValid(object.body) {
		return {}
	}
	rotation := b3.Body_GetRotation(object.body)
	info := prefab(object.prefab)
	return {
		center = b3.ToVec3(b3.Body_GetPosition(object.body)),
		half_extents = info.half_extents,
		color = object.color,
		rotation = {rotation.x, rotation.y, rotation.z, rotation.w},
		emissive = object.light.emissive,
	}
}

simulation_create_object :: proc(sim: ^Simulation, spawn: Object_Spawn) -> Object_Id {
	light := spawn_light(spawn)
	if light.active && light.kind != lamp_kind_for_body(spawn.body_mode) {
		return INVALID_OBJECT_ID
	}
	color := prefab_color(spawn.prefab)
	if light.active {
		color = light_color4(light.color)
	}
	return create_object(sim, spawn, color, light, false)
}

simulation_remove_object :: proc(sim: ^Simulation, id: Object_Id) -> bool {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return false
	}

	b3.DestroyBody(sim.objects[index].body)
	for next in index ..< len(sim.objects) - 1 {
		sim.objects[next] = sim.objects[next + 1]
	}
	resize(&sim.objects, len(sim.objects) - 1)
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
	if object.light.active {
		object.light.kind = lamp_kind_for_body(mode)
	}
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
	clear(&sim.objects)
	sim.next_object_id = 1

	colors := INITIAL_CRATE_COLORS
	for position, index in INITIAL_CRATE_POSITIONS {
		_ = create_object(
			sim,
			{
				prefab = .Crate,
				body_mode = .Dynamic,
				center = position,
				yaw_rad = 0.0,
			},
			colors[index],
			{},
			true,
		)
	}
	for lamp in INITIAL_LAMPS {
		light := prefab_light(lamp.prefab)
		light.kind = .Static_Fixture
		_ = create_object(
			sim,
			{
				name = lamp.name,
				prefab = lamp.prefab,
				body_mode = .Static,
				center = lamp.position,
			},
			prefab_color(lamp.prefab),
			light,
			true,
		)
	}
}

simulation_reset_scene :: proc(sim: ^Simulation) {
	simulation_reset_objects(sim)
	simulation_reset(sim)
}

// A spawn may omit the light; a lamp then falls back to its prefab defaults.
@(private)
spawn_light :: proc(spawn: Object_Spawn) -> Light_Settings {
	if !prefab_has_light(spawn.prefab) {
		return {}
	}
	if spawn.light.active {
		return spawn.light
	}
	return prefab_light(spawn.prefab)
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
