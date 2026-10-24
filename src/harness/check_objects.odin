#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strconv"

@(private)
objects_field :: proc(objects: []Object_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	if head == "count" {
		return {kind = .Number, number = f64(len(objects))}, ""
	}

	id, parse_ok := strconv.parse_int(head)
	if !parse_ok || id <= 0 {
		return {}, fmt.aprintf("object id %q is not valid", head, allocator = context.allocator)
	}
	object, found := find_object_state(objects, id)
	if !found {
		return {}, fmt.aprintf("object id %d is out of range", id, allocator = context.allocator)
	}
	if !has_tail {
		return {}, "object needs a field"
	}

	property, axis, has_axis := split_field(tail)
	switch property {
	case "id":
		return {kind = .Number, number = f64(object.id)}, ""
	case "prefab":
		return {kind = .String, text = object.prefab}, ""
	case "body":
		return {kind = .String, text = object.body}, ""
	case "position":
		if !has_axis {
			return {}, "object position needs an axis"
		}
		return vec_field(object.position, axis)
	case "rotation":
		if !has_axis {
			return {}, "object rotation needs an axis"
		}
		return quat_field(object.rotation, axis)
	case "scale":
		return {kind = .Number, number = f64(object.scale)}, ""
	case "spawn_age":
		return {kind = .Number, number = f64(object.spawn_age)}, ""
	}
	return {}, fmt.aprintf("unknown object field %q", tail, allocator = context.allocator)
}

@(private)
find_object_state :: proc(objects: []Object_State, id: int) -> (Object_State, bool) {
	for object in objects {
		if object.id == u32(id) {
			return object, true
		}
	}
	return {}, false
}
