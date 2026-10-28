#+vet explicit-allocators
package harness

import "base:runtime"
import "core:reflect"
import "core:strings"

schema_state_paths :: proc(allocator: runtime.Allocator) -> []string {
	paths := make([dynamic]string, 0, 192, allocator)
	schema_collect_paths(typeid_of(State), "", &paths, allocator)
	append(&paths, strings.clone("objects.count", allocator))
	append(&paths, strings.clone("static_boxes.count", allocator))
	return paths[:]
}

@(private)
schema_collect_paths :: proc(
	id: typeid,
	prefix: string,
	paths: ^[dynamic]string,
	allocator: runtime.Allocator,
) {
	ti := runtime.type_info_base(type_info_of(id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Struct:
		for field in reflect.struct_fields_zipped(id) {
			json_name := reflect.struct_tag_get(field.tag, "json")
			if index := strings.index_byte(json_name, ','); index >= 0 {
				json_name = json_name[:index]
			}
			if json_name == "" {
				json_name = field.name
			}
			separator := prefix == "" ? "" : "."
			path := strings.concatenate({prefix, separator, json_name}, allocator)
			if prefix == "" && json_name == "objects" {
				schema_collect_paths(typeid_of(Object_State), "objects.1", paths, allocator)
				delete(path, allocator)
				continue
			}
			schema_collect_paths(field.type.id, path, paths, allocator)
			delete(path, allocator)
		}
	case runtime.Type_Info_Slice:
		path := strings.concatenate({prefix, ".0"}, allocator)
		schema_collect_paths(info.elem.id, path, paths, allocator)
		delete(path, allocator)
	case runtime.Type_Info_Array:
		path := strings.concatenate({prefix, ".0"}, allocator)
		schema_collect_paths(info.elem.id, path, paths, allocator)
		delete(path, allocator)
	case:
		append(paths, strings.clone(prefix, allocator))
	}
}
