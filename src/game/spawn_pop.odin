#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import b3 "libs:box3d"
import "src:geometry"

SPAWN_POP_DURATION :: 0.28
SPAWN_POP_MIN_SCALE :: 0.01
// A back factor of 1.5 peaks at 1.08, the requested 8 percent overshoot.
SPAWN_POP_BACK_FACTOR :: 1.5

spawn_pop_scale :: proc(age: f32) -> f32 {
	if age >= SPAWN_POP_DURATION {
		return 1.0
	}
	progress := clamp(age / SPAWN_POP_DURATION, 0.0, 1.0)
	return max(ease_out_back(progress, SPAWN_POP_BACK_FACTOR), SPAWN_POP_MIN_SCALE)
}

simulation_object_scale :: proc(sim: ^Simulation, id: Object_Id) -> f32 {
	object, ok := simulation_object_find(sim, id)
	if !ok {
		return 1.0
	}
	return object_spawn_scale(sim, object)
}

simulation_object_spawn_age :: proc(sim: ^Simulation, id: Object_Id) -> f32 {
	object, ok := simulation_object_find(sim, id)
	if !ok || object.settled {
		return 0.0
	}
	return max(sim.time - object.spawn_time, 0.0)
}

simulation_object_visual_box :: proc(sim: ^Simulation, id: Object_Id) -> geometry.Box {
	object, ok := simulation_object_find(sim, id)
	if !ok {
		return {}
	}
	box := object_box(object)
	scale := object_spawn_scale(sim, object)
	if scale == 1.0 {
		return box
	}

	aabb := oriented_aabb_half_extents(box.half_extents, transmute(b3.Quat)box.rotation)
	box.half_extents = box.half_extents * scale
	box.center.y += (scale - 1.0) * aabb.y
	return box
}

// Undo and redo restore snapshots at full size; only fresh placements pop.
simulation_restore_object :: proc(sim: ^Simulation, spawn: Object_Spawn) -> Object_Id {
	light := spawn_light(spawn)
	color := prefab_color(spawn.prefab)
	if light.active {
		color = light_color4(light.color)
	}
	return create_object(sim, spawn, color, light, true)
}

@(private)
object_spawn_scale :: proc(sim: ^Simulation, object: Placed_Object) -> f32 {
	if object.settled {
		return 1.0
	}
	return spawn_pop_scale(sim.time - object.spawn_time)
}

@(private)
ease_out_back :: proc(progress, back_factor: f32) -> f32 {
	shifted := progress - 1.0
	return 1.0 +
	       (back_factor + 1.0) * shifted * shifted * shifted +
	       back_factor * shifted * shifted
}
