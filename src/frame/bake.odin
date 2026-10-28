#+vet explicit-allocators
package frame

import "src:bake"
import "src:game"

// The static bake input is exactly the arena boxes, placed static bodies, and
// static fixtures. Dynamic lamps and dynamic bodies never enter it.
build_bake_input :: proc(sim: ^game.Simulation, scratch: ^Scratch) -> bake.Static {
	clear(&scratch.bake_boxes)
	clear(&scratch.bake_lights)

	arena_count := 0
	for box, index in game.arena_static_boxes() {
		append(&scratch.bake_boxes, bake.Box_Entry {
			source = .Arena,
			id = u32(index),
			box = box,
		})
		arena_count += 1
	}
	for object in game.simulation_objects(sim) {
		box := game.simulation_object_box(sim, object.id)
		if object.body_mode == .Static {
			insert_box(&scratch.bake_boxes, arena_count, bake.Box_Entry {
				source = .Placed,
				id = u32(object.id),
				box = box,
			})
		}
		if object.light.active && object.light.kind == .Static_Fixture {
			insert_light(&scratch.bake_lights, bake.Light_Entry {
				id = u32(object.id),
				position = box.center,
				color = game.light_color_rgb(object.light.color),
				intensity = object.light.intensity,
				range = object.light.range,
				emissive = object.light.emissive,
			})
		}
	}
	return {
		boxes = scratch.bake_boxes[:],
		lights = scratch.bake_lights[:],
	}
}

// Placed entries sort by object id so an undo that restores the same objects in
// a different order keeps the key stable.
@(private)
insert_box :: proc(entries: ^[dynamic]bake.Box_Entry, start: int, entry: bake.Box_Entry) {
	index := start
	for index < len(entries) && entries[index].id < entry.id {
		index += 1
	}
	inject_at(entries, index, entry)
}

@(private)
insert_light :: proc(entries: ^[dynamic]bake.Light_Entry, entry: bake.Light_Entry) {
	index := 0
	for index < len(entries) && entries[index].id < entry.id {
		index += 1
	}
	inject_at(entries, index, entry)
}
