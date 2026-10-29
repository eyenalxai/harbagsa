#+vet explicit-allocators
package harness

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"

import "src:frame"

Schema_Field :: struct {
	name: string `json:"name"`,
	type: string `json:"type"`,
	unit: string `json:"unit,omitempty"`,
}

Schema_Command :: struct {
	name:        string         `json:"name"`,
	description: string         `json:"description"`,
	backend:     string         `json:"backend"`,
	fields:      []Schema_Field `json:"fields"`,
}

Schema_Unit :: struct {
	suffix: string `json:"suffix"`,
	unit:   string `json:"unit"`,
}

Schema_Document :: struct {
	version:         int              `json:"version"`,
	commands:        []Schema_Command `json:"commands"`,
	scenario_keys:   []string         `json:"scenario_keys"`,
	capture_targets: []string         `json:"capture_targets"`,
	capture_views:   []string         `json:"capture_views"`,
	capture_formats: []string         `json:"capture_formats"`,
	state_fields:    []string         `json:"state_fields"`,
	units:           []Schema_Unit    `json:"units"`,
}

SCENARIO_KEYS := []string {
	"version",
	"note",
	"view",
	"commands",
	"renderer_debug",
	"requires",
	"size",
	"extends",
	"parameters",
}

CAPTURE_TARGETS := []string{"color", "velocity", "history", "depth", "scene_color"}
CAPTURE_FORMATS := []string{"png", "float", "raw", "stats", "profile"}

SCHEMA_UNITS := [?]Schema_Unit {
	{"_deg", "degrees"},
	{"_px", "pixels"},
	{"at", "pixels"},
	{"_seconds", "seconds"},
	{"_ms", "milliseconds"},
	{"_m", "metres"},
	{"frames", "frames"},
	{"alpha", "fraction"},
	{"type_weight", "font weight"},
	{"scale", "factor"},
	{"histogram", "bins"},
	{"synthetic_lights", "count"},
}

schema_backend_name :: proc(backend: Command_Backend) -> string {
	switch backend {
	case .None:
		return "none"
	case .Optional:
		return "optional"
	case .Required:
		return "required"
	}
	return "none"
}

schema_command_fields :: proc(row: ^Command_Row, allocator: runtime.Allocator) -> []Schema_Field {
	fields := make([dynamic]Schema_Field, 0, 8, allocator)
	// A scene command spreads its blocks at the top level, not under a
	// "scene" key, so the schema follows the parser rather than the struct.
	if row.kind == .Scene {
		schema_append_fields(
			typeid_of(frame.Scene),
			[]string{"settings", "view", "renderer_debug"},
			&fields,
			allocator,
		)
		schema_append_fields(row.value_type, []string{"scene"}, &fields, allocator)
		return fields[:]
	}
	schema_append_fields(row.value_type, nil, &fields, allocator)
	return fields[:]
}

@(private)
schema_append_fields :: proc(
	id: typeid,
	skip: []string,
	fields: ^[dynamic]Schema_Field,
	allocator: runtime.Allocator,
) {
	for field in reflect.struct_fields_zipped(id) {
		if string_in(field.name, skip) ||
		   strings.has_prefix(field.name, "has_") ||
		   field.name == "reset" {
			continue
		}
		json_name := reflect.struct_tag_get(field.tag, "json")
		if json_name == "-" {
			continue
		}
		// A `using` field is flattened at the access level, and the parser
		// accepts its keys at the top level, so the schema lists its fields in
		// place of the container.
		if field.is_using {
			schema_append_fields(field.type.id, skip, fields, allocator)
			continue
		}
		if index := strings.index_byte(json_name, ','); index >= 0 {
			json_name = json_name[:index]
		}
		name := json_name == "" ? field.name : json_name
		append(fields, {
			name = strings.clone(name, allocator),
			type = schema_type_name(field.type.id, allocator),
			unit = schema_field_unit(name),
		})
	}
}

schema_type_name :: proc(id: typeid, allocator: runtime.Allocator) -> string {
	ti := type_info_of(id)
	if named, ok := ti.variant.(runtime.Type_Info_Named); ok {
		name := named.name
		if index := strings.last_index_byte(name, '.'); index >= 0 {
			name = name[index + 1:]
		}
		if strings.has_prefix(name, "Maybe(") {
			base := runtime.type_info_base(named.base)
			if info_union, is_union := base.variant.(runtime.Type_Info_Union);
			   is_union && len(info_union.variants) > 0 {
				inner := schema_type_name(info_union.variants[0].id, context.temp_allocator)
				return fmt.aprintf("%s?", inner, allocator = allocator)
			}
		}
		return strings.clone(name, allocator)
	}
	base := runtime.type_info_base(ti)
	#partial switch info in base.variant {
	case runtime.Type_Info_Integer:
		return strings.clone("integer", allocator)
	case runtime.Type_Info_Float:
		return strings.clone("number", allocator)
	case runtime.Type_Info_Boolean:
		return strings.clone("boolean", allocator)
	case runtime.Type_Info_String:
		return strings.clone("string", allocator)
	case runtime.Type_Info_Array:
		element := schema_type_name(info.elem.id, context.temp_allocator)
		return fmt.aprintf("[%d]%s", info.count, element, allocator = allocator)
	case runtime.Type_Info_Slice, runtime.Type_Info_Dynamic_Array:
		return strings.clone("array", allocator)
	case runtime.Type_Info_Union:
		if len(info.variants) > 0 {
			name := schema_type_name(info.variants[0].id, context.temp_allocator)
			return fmt.aprintf("%s?", name, allocator = allocator)
		}
		return strings.clone("optional", allocator)
	case runtime.Type_Info_Enum:
		return strings.clone("enum", allocator)
	case runtime.Type_Info_Struct:
		return strings.clone("object", allocator)
	case runtime.Type_Info_Pointer:
		return strings.clone("pointer", allocator)
	}
	return strings.clone("value", allocator)
}

schema_field_unit :: proc(name: string) -> string {
	for entry in SCHEMA_UNITS {
		if name == entry.suffix || strings.has_suffix(name, entry.suffix) {
			return entry.unit
		}
	}
	return ""
}
