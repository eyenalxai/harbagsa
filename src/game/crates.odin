#+vet explicit-allocators
package game

import b3 "libs:box3d"
import "src:geometry"

Crate :: struct {
	body:         b3.BodyId,
	half_extents: b3.Vec3,
	color:        [4]f32,
}

simulation_crate_count :: proc(sim: ^Simulation) -> int {
	return sim.crate_count
}

simulation_crate_body :: proc(sim: ^Simulation, index: int) -> b3.BodyId {
	if index < 0 || index >= sim.crate_count {
		return {}
	}
	return sim.crates[index].body
}

simulation_crate_box :: proc(sim: ^Simulation, index: int) -> geometry.Box {
	if index < 0 || index >= sim.crate_count {
		return {}
	}
	crate := sim.crates[index]
	rotation := b3.Body_GetRotation(crate.body)
	return {
		center = b3.ToVec3(b3.Body_GetPosition(crate.body)),
		half_extents = crate.half_extents,
		color = crate.color,
		rotation = {rotation.x, rotation.y, rotation.z, rotation.w},
	}
}

simulation_add_crate :: proc(
	sim: ^Simulation,
	center: b3.Vec3,
	half_extents: b3.Vec3,
	color: [4]f32,
) -> int {
	if sim.crate_count >= MAX_CRATES {
		return -1
	}
	body := create_crate_body(sim, center, half_extents)
	if !b3.Body_IsValid(body) {
		return -1
	}

	index := sim.crate_count
	sim.crates[index] = {
		body = body,
		half_extents = half_extents,
		color = color,
	}
	sim.crate_count += 1
	return index
}

// Added crates cycle through the initial palette so neighbours stay distinct.
simulation_add_default_crate :: proc(sim: ^Simulation, center: b3.Vec3) -> int {
	color := initial_crate_colors()[sim.next_crate_color]
	index := simulation_add_crate(sim, center, CRATE_HALF_EXTENTS, color)
	if index >= 0 {
		sim.next_crate_color = (sim.next_crate_color + 1) % INITIAL_CRATE_COUNT
	}
	return index
}

simulation_remove_crate :: proc(sim: ^Simulation, index: int) -> bool {
	if index < 0 || index >= sim.crate_count {
		return false
	}

	b3.DestroyBody(sim.crates[index].body)
	for next in index ..< sim.crate_count - 1 {
		sim.crates[next] = sim.crates[next + 1]
	}
	sim.crate_count -= 1
	sim.crates[sim.crate_count] = {}
	return true
}

simulation_move_crate :: proc(sim: ^Simulation, index: int, center: b3.Vec3) {
	body := simulation_crate_body(sim, index)
	if !b3.Body_IsValid(body) {
		return
	}

	// Body_SetTransform does not wake the body or clear momentum.
	b3.Body_SetTransform(body, center, b3.Body_GetRotation(body))
	b3.Body_SetLinearVelocity(body, b3.Vec3_zero)
	b3.Body_SetAngularVelocity(body, b3.Vec3_zero)
	b3.Body_SetAwake(body, true)
}

simulation_reset_crates :: proc(sim: ^Simulation) {
	for index in 0 ..< sim.crate_count {
		if b3.Body_IsValid(sim.crates[index].body) {
			b3.DestroyBody(sim.crates[index].body)
		}
	}
	sim.crate_count = 0
	sim.next_crate_color = 0

	for position, index in INITIAL_CRATE_POSITIONS {
		_ = simulation_add_crate(sim, position, CRATE_HALF_EXTENTS, initial_crate_colors()[index])
	}
}

simulation_reset_scene :: proc(sim: ^Simulation) {
	simulation_reset_crates(sim)
	simulation_reset(sim)
}

@(private)
create_crate_body :: proc(sim: ^Simulation, center: b3.Vec3, half_extents: b3.Vec3) -> b3.BodyId {
	body_def := b3.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = center
	body_id := b3.CreateBody(sim.world_id, body_def)
	if !b3.Body_IsValid(body_id) {
		return {}
	}

	hull := b3.MakeBoxHull(half_extents.x, half_extents.y, half_extents.z)
	shape_def := b3.DefaultShapeDef()
	shape_def.density = CRATE_DENSITY
	shape := b3.CreateHullShape(body_id, shape_def, &hull.base)
	if !b3.Shape_IsValid(shape) {
		b3.DestroyBody(body_id)
		return {}
	}
	return body_id
}
