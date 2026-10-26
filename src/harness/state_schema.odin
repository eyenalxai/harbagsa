#+vet explicit-allocators
package harness

import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "base:runtime"

// The State struct and its json tags are the schema. A path walks the same
// fields the JSON writer emits, so a check cannot drift from the document.
state_field :: proc(state: State, path: string) -> (Check_Value, string) {
	head, rest, has_tail := split_field(path)
	if head == "static_boxes" {
		if rest == "count" {
			return {kind = .Number, number = f64(len(state.static_boxes))}, ""
		}
		if !has_tail {
			return {}, format_error("%s", "static_boxes needs a field")
		}
		value: any = state.static_boxes
		return resolve_state_path(value, rest, path)
	}
	if head == "objects" {
		if rest == "count" {
			return {kind = .Number, number = f64(len(state.objects))}, ""
		}
		if !has_tail {
			return {}, format_error("%s", "objects needs a field")
		}
		handle, object_path, has_object_path := split_field(rest)
		object: Object_State
		found: bool
		if id, id_ok := parse_object_id(handle); id_ok {
			if id <= 0 {
				return {}, fmt.aprintf("object id %q is not valid", handle, allocator = context.allocator)
			}
			object, found = find_object_state(state.objects, id)
		} else {
			object, found = find_object_state_by_name(state.objects, handle)
		}
		if !found {
			return {}, fmt.aprintf("object %q is not in the list", handle, allocator = context.allocator)
		}
		if !has_object_path {
			return {}, format_error("%s", "object needs a field")
		}
		value: any = object
		return resolve_state_path(value, object_path, path)
	}
	value: any = state
	return resolve_state_path(value, path, path)
}

@(private)
resolve_state_path :: proc(value: any, path, full_path: string) -> (Check_Value, string) {
	if path == "" {
		return state_scalar(value, full_path)
	}
	head, tail, has_tail := split_field(path)
	if !has_tail {
		tail = ""
	}
	ti := runtime.type_info_base(type_info_of(value.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Struct:
		field := struct_field_by_json_name(value, head)
		if field == nil {
			return {}, fmt.aprintf("unknown state field %q", full_path, allocator = context.allocator)
		}
		return resolve_state_path(field, tail, full_path)
	case runtime.Type_Info_Slice:
		index, ok := strconv.parse_int(head)
		if !ok || index < 0 {
			return {}, fmt.aprintf("slice index %q is not valid", head, allocator = context.allocator)
		}
		slice := cast(^runtime.Raw_Slice)value.data
		if index >= slice.len {
			return {}, fmt.aprintf("slice index %d is out of range", index, allocator = context.allocator)
		}
		element := any {
			data = rawptr(uintptr(slice.data) + uintptr(index) * uintptr(info.elem.size)),
			id   = info.elem.id,
		}
		return resolve_state_path(element, tail, full_path)
	case runtime.Type_Info_Array:
		index, ok := strconv.parse_int(head)
		if !ok || index < 0 || index >= int(info.count) {
			return {}, fmt.aprintf("array index %q is out of range", head, allocator = context.allocator)
		}
		element := any {
			data = rawptr(uintptr(value.data) + uintptr(index) * uintptr(info.elem.size)),
			id   = info.elem.id,
		}
		return resolve_state_path(element, tail, full_path)
	}
	return {}, fmt.aprintf("state field %q is not a container", full_path, allocator = context.allocator)
}

@(private)
state_scalar :: proc(value: any, full_path: string) -> (Check_Value, string) {
	ti := runtime.type_info_base(type_info_of(value.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Boolean:
		boolean, ok := reflect.as_bool(value)
		if ok {
			return {kind = .Bool, boolean = boolean}, ""
		}
	case runtime.Type_Info_Integer:
		number, ok := reflect.as_i64(value)
		if ok {
			return {kind = .Number, number = f64(number)}, ""
		}
	case runtime.Type_Info_Float:
		number, ok := reflect.as_f64(value)
		if ok {
			return {kind = .Number, number = number}, ""
		}
	case runtime.Type_Info_String:
		text, ok := reflect.as_string(value)
		if ok {
			return {kind = .String, text = text}, ""
		}
	case runtime.Type_Info_Enum:
		name, ok := reflect.enum_name_from_value_any(value)
		if ok {
			return {kind = .String, text = name}, ""
		}
	}
	return {}, fmt.aprintf("state field %q is not a scalar", full_path, allocator = context.allocator)
}

@(private)
struct_field_by_json_name :: proc(value: any, name: string) -> any {
	for field in reflect.struct_fields_zipped(value.id) {
		json_name := reflect.struct_tag_get(field.tag, "json")
		if json_name == "" {
			json_name = field.name
		}
		if option := strings.index_byte(json_name, ','); option >= 0 {
			json_name = json_name[:option]
		}
		if json_name == name {
			return reflect.struct_field_value(value, field)
		}
	}
	return nil
}

@(private)
parse_object_id :: proc(text: string) -> (int, bool) {
	if text == "" {
		return 0, false
	}
	for character in text {
		if character < '0' || character > '9' {
			return 0, false
		}
	}
	return strconv.parse_int(text, 10)
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

@(private)
find_object_state_by_name :: proc(objects: []Object_State, name: string) -> (Object_State, bool) {
	if name == "" {
		return {}, false
	}
	for object in objects {
		if object.name == name {
			return object, true
		}
	}
	return {}, false
}

@(private)
split_field :: proc(path: string) -> (head, tail: string, has_tail: bool) {
	index := -1
	for character, position in path {
		if character == '.' {
			index = position
			break
		}
	}
	if index < 0 {
		return path, "", false
	}
	return path[:index], path[index + 1:], true
}
