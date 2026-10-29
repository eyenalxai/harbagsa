#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import b3 "libs:box3d"

simulation_convert_object :: proc(sim: ^Simulation, id: Object_Id, mode: Body_Mode) -> bool {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return false
	}
	object := &sim.objects[index]
	// A lamp body follows its kind. The kind path owns that conversion.
	if object.light.active {
		return false
	}
	return convert_object_body(sim, object, mode)
}

// Switching a lamp kind forces the matching body. The old body is replaced only
// after the new one exists, so a failed conversion leaves the lamp intact.
simulation_set_lamp_kind :: proc(sim: ^Simulation, id: Object_Id, kind: Lamp_Kind) -> bool {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return false
	}
	object := &sim.objects[index]
	if !object.light.active {
		return false
	}
	if object.light.kind == kind {
		return true
	}
	if !convert_object_body(sim, object, lamp_kind_body(kind)) {
		return false
	}
	object.light.kind = kind
	return true
}

@(private)
convert_object_body :: proc(sim: ^Simulation, object: ^Placed_Object, mode: Body_Mode) -> bool {
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
