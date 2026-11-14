#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:renderer"

execute_ui_tree :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if session.render.backend == nil {
		return format_error("%s", "ui_tree requires rendering")
	}
	clear(&session.ui_actions)
	count: u32
	pointer := renderer.ui_tree_json(&count)
	if pointer == nil || count == 0 {
		return format_error("%s", "the UI shim returned no tree")
	}
	value, parse_error := json.parse_string(string(pointer[:count]), .JSON, true, session.allocator)
	if parse_error != .None {
		return format_error("the UI tree is not valid JSON: %v", parse_error)
	}
	defer json.destroy_value(value, session.allocator)
	array, ok := json_array(value)
	if !ok {
		return format_error("%s", "the UI tree is not an array")
	}
	nodes := make([]Ui_Tree_Node, len(array), session.allocator)
	for element, index in array {
		node, node_error := parse_ui_tree_node(element, session.allocator)
		if node_error != "" {
			ui_tree_nodes_destroy(nodes, session.allocator)
			return node_error
		}
		nodes[index] = node
	}
	session_ui_set_tree(session, nodes)
	return ""
}

@(private)
parse_ui_tree_node :: proc(value: json.Value, allocator: mem.Allocator) -> (Ui_Tree_Node, string) {
	object, ok := json_object(value)
	if !ok {
		return {}, format_error("%s", "a UI tree element is not an object")
	}
	path_value, path_field_error := tree_field(object, "path")
	if path_field_error != "" {
		return {}, path_field_error
	}
	path, path_ok := json_string(path_value)
	if !path_ok {
		return {}, tree_type_error("path", "a string")
	}
	if path == "" {
		return {}, format_error("%s", "a UI tree element has no path")
	}
	role_value, role_field_error := tree_field(object, "role")
	if role_field_error != "" {
		return {}, role_field_error
	}
	role, role_ok := json_string(role_value)
	if !role_ok {
		return {}, tree_type_error("role", "a string")
	}
	key := ""
	if key_value, has := json_get(object, "key"); has && !json_is_null(key_value) {
		key, ok = json_string(key_value)
		if !ok {
			return {}, tree_type_error("key", "a string or null")
		}
	}
	label := ""
	if label_value, has := json_get(object, "label"); has && !json_is_null(label_value) {
		label, ok = json_string(label_value)
		if !ok {
			return {}, tree_type_error("label", "a string or null")
		}
	}
	text := ""
	if text_value, has := json_get(object, "text"); has && !json_is_null(text_value) {
		text, ok = json_string(text_value)
		if !ok {
			return {}, tree_type_error("text", "a string or null")
		}
	}
	focused_value, focused_field_error := tree_field(object, "focused")
	if focused_field_error != "" {
		return {}, focused_field_error
	}
	focused, focused_ok := json_boolean(focused_value)
	if !focused_ok {
		return {}, tree_type_error("focused", "a boolean")
	}
	visible_value, visible_field_error := tree_field(object, "focus_visible")
	if visible_field_error != "" {
		return {}, visible_field_error
	}
	visible, visible_ok := json_boolean(visible_value)
	if !visible_ok {
		return {}, tree_type_error("focus_visible", "a boolean")
	}
	selected_value, selected_field_error := tree_field(object, "selected")
	if selected_field_error != "" {
		return {}, selected_field_error
	}
	selected, selected_ok := json_boolean(selected_value)
	if !selected_ok {
		return {}, tree_type_error("selected", "a boolean")
	}
	hover_value, hover_field_error := tree_field(object, "hover")
	if hover_field_error != "" {
		return {}, hover_field_error
	}
	hover, hover_ok := json_number(hover_value)
	if !hover_ok {
		return {}, tree_type_error("hover", "a number")
	}
	press_value, press_field_error := tree_field(object, "press")
	if press_field_error != "" {
		return {}, press_field_error
	}
	press, press_ok := json_number(press_value)
	if !press_ok {
		return {}, tree_type_error("press", "a number")
	}
	opacity_value, opacity_field_error := tree_field(object, "opacity")
	if opacity_field_error != "" {
		return {}, opacity_field_error
	}
	opacity, opacity_ok := json_number(opacity_value)
	if !opacity_ok {
		return {}, tree_type_error("opacity", "a number")
	}
	rect_value, rect_field_error := tree_field(object, "rect")
	if rect_field_error != "" {
		return {}, rect_field_error
	}
	rect, rect_error := tree_vec4_value(rect_value, "rect")
	if rect_error != "" {
		return {}, rect_error
	}
	parent_value, parent_field_error := tree_field(object, "parent")
	if parent_field_error != "" {
		return {}, parent_field_error
	}
	parent, parent_ok := json_integer(parent_value)
	if !parent_ok {
		return {}, tree_type_error("parent", "an integer")
	}
	return {
		path          = strings.clone(path, allocator),
		key           = key == "" ? "" : strings.clone(key, allocator),
		role          = strings.clone(role, allocator),
		label         = label == "" ? "" : strings.clone(label, allocator),
		text          = text == "" ? "" : strings.clone(text, allocator),
		focused       = focused,
		focus_visible = visible,
		selected      = selected,
		hover         = f32(hover),
		press         = f32(press),
		opacity       = f32(opacity),
		rect          = rect,
		parent        = parent,
	}, ""
}

@(private)
tree_field :: proc(object: json.Object, name: string) -> (json.Value, string) {
	value, has := json_get(object, name)
	if !has {
		return {}, format_error("UI tree field %q is missing", name)
	}
	return value, ""
}

@(private)
tree_type_error :: proc(name, expected: string) -> string {
	return format_error("UI tree field %q must be %s", name, expected)
}

@(private)
tree_vec4_value :: proc(value: json.Value, name: string) -> ([4]f32, string) {
	array, ok := json_array(value)
	if !ok || len(array) != 4 {
		return {}, tree_type_error(name, "four numbers")
	}
	result: [4]f32
	for element, index in array {
		number, number_ok := json_number(element)
		if !number_ok {
			return {}, tree_type_error(name, "four numbers")
		}
		result[index] = f32(number)
	}
	return result, ""
}