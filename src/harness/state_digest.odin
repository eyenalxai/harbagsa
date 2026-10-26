#+vet explicit-allocators
package harness

import "core:mem"

import "core:reflect"
import "base:runtime"

import b3 "libs:box3d"

import "src:digest"
import "src:game"

// The State struct is the schema. The digest walks the same fields the JSON
// writer emits and skips the fields tagged `digest:"-"`.
state_digest :: proc(state: State, allocator: mem.Allocator) -> string {
	hash := digest.fnv()
	value: any = state
	digest_value(&hash, value)
	return digest.hex(hash, allocator)
}

@(private)
digest_value :: proc(hash: ^digest.FNV, value: any) {
	ti := runtime.type_info_base(type_info_of(value.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Struct:
		for field in reflect.struct_fields_zipped(value.id) {
			if reflect.struct_tag_get(field.tag, "digest") == "-" {
				continue
			}
			digest_value(hash, reflect.struct_field_value(value, field))
		}
	case runtime.Type_Info_Slice:
		slice := cast(^runtime.Raw_Slice)value.data
		digest.write_u64(hash, u64(slice.len))
		for index in 0 ..< slice.len {
			element := any {
				data = rawptr(uintptr(slice.data) + uintptr(index) * uintptr(info.elem.size)),
				id   = info.elem.id,
			}
			digest_value(hash, element)
		}
	case runtime.Type_Info_Array:
		digest.write_u64(hash, u64(info.count))
		for index in 0 ..< int(info.count) {
			element := any {
				data = rawptr(uintptr(value.data) + uintptr(index) * uintptr(info.elem.size)),
				id   = info.elem.id,
			}
			digest_value(hash, element)
		}
	case runtime.Type_Info_Boolean:
		boolean, ok := reflect.as_bool(value)
		if ok {
			digest.write_bool(hash, boolean)
		}
	case runtime.Type_Info_Integer:
		number, ok := reflect.as_i64(value)
		if ok {
			digest.write_i64(hash, number)
		}
	case runtime.Type_Info_Float:
		number, ok := reflect.as_f64(value)
		if ok {
			digest.write_f32(hash, f32(number))
		}
	case runtime.Type_Info_String:
		text, ok := reflect.as_string(value)
		if ok {
			digest.write_string(hash, text)
		}
	case runtime.Type_Info_Enum:
		name, ok := reflect.enum_name_from_value_any(value)
		if ok {
			digest.write_string(hash, name)
		}
	}
}

@(private)
vec_state :: proc(value: b3.Vec3) -> Vec_State {
	return {x = value.x, y = value.y, z = value.z}
}

@(private)
quat_state :: proc(value: [4]f32) -> Quat_State {
	return {x = value[0], y = value[1], z = value[2], w = value[3]}
}

@(private)
color_state :: proc(value: [4]f32) -> Color_State {
	return {r = value[0], g = value[1], b = value[2], a = value[3]}
}

@(private)
menu_selected_blocked :: proc(menu: ^game.Menu_State) -> bool {
	if !menu.open {
		return false
	}
	row := game.MENU_ITEM_ROWS[int(menu.selected)]
	return menu.rows[row].blocked
}
