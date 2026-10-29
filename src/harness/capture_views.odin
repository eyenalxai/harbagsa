#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"

import "src:renderer"

MAX_CAPTURE_VIEWS :: len(renderer.CAPTURE_VIEW_NAMES)

@(private)
parse_capture_views :: proc(
	value: json.Value,
	name: string,
	has_name: bool,
	allocator: mem.Allocator,
) -> (views: []renderer.Capture_View, error: string) {
	array, array_ok := json_array(value)
	if !array_ok || len(array) == 0 || len(array) > MAX_CAPTURE_VIEWS {
		return nil, format_error(
			"'views' must be an array of 1 to %d view names",
			MAX_CAPTURE_VIEWS,
		)
	}
	views = make([]renderer.Capture_View, len(array), allocator)
	seen: renderer.Capture_Views
	for item, index in array {
		view_name, name_ok := json_string(item)
		view, view_ok := renderer.capture_view_parse(view_name)
		if !name_ok || !view_ok {
			delete(views, allocator)
			return nil, format_error(
				"'views' must name beauty, direct, lightmap, probe, emissive, shadow, lightmap_grid, or probe_cell",
			)
		}
		if view in seen {
			delete(views, allocator)
			return nil, format_error("view %q appears twice", view_name)
		}
		seen |= {view}
		views[index] = view
		// The combined name is the one the report writes, so the name rule
		// applies to it, not to the base name alone.
		if has_name && !valid_capture_name(capture_view_request_name(name, view, context.temp_allocator)) {
			delete(views, allocator)
			return nil, format_error(
				"capture name %q with view %q is over the name limit",
				name,
				view_name,
			)
		}
	}
	return views, ""
}

capture_view_request_name :: proc(
	base: string,
	view: renderer.Capture_View,
	allocator: mem.Allocator,
) -> string {
	return fmt.aprintf("%s-%s", base, renderer.capture_view_name(view), allocator = allocator)
}
