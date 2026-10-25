#+vet explicit-allocators
package harness

import "base:runtime"
import "core:reflect"
import "core:strings"

schema_state_paths :: proc(allocator: runtime.Allocator) -> []string {
	paths := make([dynamic]string, 0, 192, allocator)
	schema_collect_paths(typeid_of(State), "", &paths, allocator)
	append(&paths, strings.clone("objects.count", allocator))
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

schema_check_fields :: proc(allocator: runtime.Allocator) -> []string {
	paths := make([dynamic]string, 0, 256, allocator)
	state_paths := schema_state_paths(allocator)
	defer delete(state_paths, allocator)
	for path in state_paths {
		append(&paths, path)
	}
	extra := [?]string {
		"render_digest",
		"capture.count",
		"capture.worst_mean_delta",
		"capture.worst_max_delta",
		"capture.worst_over_16",
		"capture.worst_over_16_fraction",
		"capture.target",
		"capture.format",
		"capture.png",
		"capture.stats.steps.count",
		"capture.stats.steps.pairs",
		"capture.stats.steps.max",
		"capture.profile.width",
		"capture.profile.low_index",
		"capture.profile.high_index",
		"capture.profile.flat",
		"capture.profile.axis",
		"capture.profile.channel",
		"capture.profile.source",
		"capture.profile.values.0",
		"capture.region.x",
		"capture.region.y",
		"capture.region.w",
		"capture.region.h",
		"capture.crop.x",
		"capture.crop.y",
		"capture.crop.w",
		"capture.crop.h",
		"capture.crop.scale",
		"capture.crop.width",
		"capture.crop.height",
		"capture.histogram.bins",
		"capture.histogram.x.0",
		"capture.histogram.y.0",
		"capture.histogram.z.0",
		"capture.histogram.w.0",
		"capture.first.stats.mean.y",
		"capture.last.stats.mean.y",
		"capture.named.<name>.stats.mean.y",
		"analysis.pairs",
		"analysis.worst_mean",
		"analysis.worst_max",
		"analysis.worst_over_16",
		"analysis.worst_over_16_fraction",
		"analysis.period.frames",
		"analysis.period.correlation",
		"analysis.bands.longest_run",
		"analysis.bands.median_run",
		"analysis.bands.levels",
		"analysis.bands.columns",
		"analysis.bands.region.x",
		"analysis.bands.region.y",
		"analysis.bands.region.w",
		"analysis.bands.region.h",
	}
	for field in extra {
		append(&paths, strings.clone(field, allocator))
	}
	channels := [?]string{"min", "max", "mean", "stddev", "gradient"}
	axes := [?]string{"x", "y", "z", "w"}
	for channel in channels {
		for axis in axes {
			append(
				&paths,
				strings.concatenate(
					{"capture.stats.", channel, ".", axis},
					allocator,
				),
			)
		}
	}
	return paths[:]
}
