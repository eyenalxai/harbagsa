#+vet explicit-allocators
#+vet !unused-procedures // the frame and the bake tool share this input
package game

import "core:mem"

import "src:bake"

Bake_Input :: struct {
	boxes:  [dynamic]bake.Box_Entry,
	lights: [dynamic]bake.Light_Entry,
}

bake_input_destroy :: proc(input: ^Bake_Input) {
	if input.boxes != nil {
		delete(input.boxes)
	}
	if input.lights != nil {
		delete(input.lights)
	}
	input^ = {}
}

// The frame and the bake input share one identity per static box.
arena_identity :: proc(index: int) -> (source: bake.Box_Source, id: u32) {
	return .Arena, u32(index)
}

placed_identity :: proc(object: Placed_Object) -> (source: bake.Box_Source, id: u32) {
	return .Placed, u32(object.id)
}

// The frame and the bake input share this rule, so it lives here.
object_has_bake_slot :: proc(object: Placed_Object) -> bool {
	return object.body_mode == .Static
}

bake_arena_slot :: proc(index: int) -> bake.Box_Slot {
	source, id := arena_identity(index)
	return {key = bake.slot_key(source, id), has_slot = true}
}

bake_placed_slot :: proc(object: Placed_Object) -> bake.Box_Slot {
	if !object_has_bake_slot(object) {
		return {}
	}
	source, id := placed_identity(object)
	return {key = bake.slot_key(source, id), has_slot = true}
}

// The static bake input is exactly the arena boxes, placed static bodies, and
// static fixtures. Dynamic lamps and dynamic bodies never enter it.
simulation_bake_input :: proc(
	sim: ^Simulation,
	input: ^Bake_Input,
	allocator: mem.Allocator,
) -> bake.Static {
	if input.boxes == nil {
		input.boxes = make([dynamic]bake.Box_Entry, 0, 0, allocator)
	}
	if input.lights == nil {
		input.lights = make([dynamic]bake.Light_Entry, 0, 0, allocator)
	}
	clear(&input.boxes)
	clear(&input.lights)

	arena_count := 0
	for box, index in arena_static_boxes() {
		source, id := arena_identity(index)
		append(&input.boxes, bake.Box_Entry{source = source, id = id, box = box})
		arena_count += 1
	}
	for object in simulation_objects(sim) {
		box := simulation_object_box(sim, object.id)
		if object_has_bake_slot(object) {
			source, id := placed_identity(object)
			insert_box(&input.boxes, arena_count, bake.Box_Entry {
				source = source,
				id = id,
				box = box,
			})
		}
		if object.light.active && object.light.kind == .Static_Fixture {
			insert_light(&input.lights, bake.Light_Entry {
				id = u32(object.id),
				position = box.center,
				color = light_color_rgb(object.light.color),
				intensity = object.light.intensity,
				range = object.light.range,
				emissive = object.light.emissive,
			})
		}
	}
	return {
		boxes = input.boxes[:],
		lights = input.lights[:],
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
