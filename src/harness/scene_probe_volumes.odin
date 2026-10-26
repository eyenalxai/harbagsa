#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:frame"

@(private)
parse_scene_probe_volumes :: proc(
	value: json.Value,
	allocator: mem.Allocator,
) -> ([]frame.Scene_Probe_Volume, string) {
	array, array_ok := json_array(value)
	if !array_ok {
		return nil, format_error("%s", "scene 'probe_volumes' must be an array")
	}
	if len(array) > frame.MAX_SCENE_PROBE_VOLUMES {
		return nil, format_error(
			"scene holds at most %d probe volumes",
			frame.MAX_SCENE_PROBE_VOLUMES,
		)
	}
	specs := make([]frame.Scene_Probe_Volume, len(array), allocator)
	ok := false
	defer if !ok {
		frame.scene_probe_volumes_destroy(specs, allocator)
	}
	total := 0
	for item, index in array {
		object, object_ok := json_object(item)
		if !object_ok {
			return nil, format_error("probe volume %d must be an object", index)
		}
		if key, unknown := json_unknown_key(object, {"name", "min", "spacing", "counts"}); unknown {
			return nil, format_error("unknown probe volume key %q", key)
		}
		min, min_ok := vec3_field(object, "min")
		spacing, spacing_ok := number_field(object, "spacing")
		counts, counts_ok := probe_counts_field(object, "counts")
		if !min_ok || !spacing_ok || !(spacing > 0) || spacing > 1000 || !counts_ok {
			return nil, format_error(
				"probe volume %d needs a position, a positive spacing, and three counts",
				index,
			)
		}
		total += int(counts.x) * int(counts.y) * int(counts.z)
		if total > frame.MAX_SCENE_PROBES {
			return nil, format_error(
				"the scene holds at most %d extra probes",
				frame.MAX_SCENE_PROBES,
			)
		}
		name := ""
		if name_value, has := json_get(object, "name"); has {
			parsed, parsed_ok := json_string(name_value)
			if !parsed_ok || !frame.scene_probe_name_valid(parsed) {
				return nil, format_error(
					"probe volume %d name must use at most %d letters, digits, '-' or '_'",
					index,
					frame.SCENE_PROBE_NAME_BYTES,
				)
			}
			name = strings.clone(parsed, allocator)
		}
		specs[index] = {
			name    = name,
			min     = min,
			spacing = f32(spacing),
			counts  = counts,
		}
	}
	ok = true
	return specs, ""
}

@(private)
probe_counts_field :: proc(object: json.Object, key: string) -> ([3]u32, bool) {
	value, has := json_get(object, key)
	if !has {
		return {}, false
	}
	array, array_ok := json_array(value)
	if !array_ok || len(array) != 3 {
		return {}, false
	}
	counts: [3]u32
	for item, index in array {
		number, number_ok := json_integer(item)
		if !number_ok || number < 1 || number > 64 {
			return {}, false
		}
		counts[index] = u32(number)
	}
	return counts, true
}
