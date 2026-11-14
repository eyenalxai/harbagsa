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
	bytes := renderer.ui_tree_bytes()
	if len(bytes) == 0 {
		return format_error("%s", "the UI shim returned no tree")
	}
	value, parse_error := json.parse_string(string(bytes), .JSON, true, session.allocator)
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
	path, field_error := tree_required_string(object, "path")
	if field_error != "" {
		return {}, field_error
	}
	role, role_error := tree_required_string(object, "role")
	if role_error != "" {
		return {}, role_error
	}
	key, key_error := tree_optional_string(object, "key")
	if key_error != "" {
		return {}, key_error
	}
	label, label_error := tree_optional_string(object, "label")
	if label_error != "" {
		return {}, label_error
	}
	text, text_error := tree_optional_string(object, "text")
	if text_error != "" {
		return {}, text_error
	}
	focused, focused_error := tree_bool(object, "focused")
	if focused_error != "" {
		return {}, focused_error
	}
	focus_visible, visible_error := tree_bool(object, "focus_visible")
	if visible_error != "" {
		return {}, visible_error
	}
	selected, selected_error := tree_bool(object, "selected")
	if selected_error != "" {
		return {}, selected_error
	}
	hover, hover_error := tree_number(object, "hover")
	if hover_error != "" {
		return {}, hover_error
	}
	press, press_error := tree_number(object, "press")
	if press_error != "" {
		return {}, press_error
	}
	opacity, opacity_error := tree_number(object, "opacity")
	if opacity_error != "" {
		return {}, opacity_error
	}
	rect, rect_error := tree_vec4(object, "rect")
	if rect_error != "" {
		return {}, rect_error
	}
	target, target_error := tree_vec4(object, "target")
	if target_error != "" {
		return {}, target_error
	}
	parent, parent_error := tree_int(object, "parent")
	if parent_error != "" {
		return {}, parent_error
	}
	if path == "" {
		return {}, format_error("%s", "a UI tree element has no path")
	}
	return {
		path          = strings.clone(path, allocator),
		key           = key == "" ? "" : strings.clone(key, allocator),
		role          = strings.clone(role, allocator),
		label         = label == "" ? "" : strings.clone(label, allocator),
		text          = text == "" ? "" : strings.clone(text, allocator),
		focused       = focused,
		focus_visible = focus_visible,
		selected      = selected,
		hover         = hover,
		press         = press,
		opacity       = opacity,
		rect          = rect,
		target        = target,
		parent        = parent,
	}, ""
}

@(private)
tree_required_string :: proc(object: json.Object, name: string) -> (string, string) {
	value, has := json_get(object, name)
	if !has {
		return "", format_error("UI tree field %q is missing", name)
	}
	text, ok := json_string(value)
	if !ok {
		return "", format_error("UI tree field %q must be a string", name)
	}
	return text, ""
}

@(private)
tree_optional_string :: proc(object: json.Object, name: string) -> (string, string) {
	value, has := json_get(object, name)
	if !has || json_is_null(value) {
		return "", ""
	}
	text, ok := json_string(value)
	if !ok {
		return "", format_error("UI tree field %q must be a string or null", name)
	}
	return text, ""
}

@(private)
tree_bool :: proc(object: json.Object, name: string) -> (bool, string) {
	value, has := json_get(object, name)
	if !has {
		return false, format_error("UI tree field %q is missing", name)
	}
	flag, ok := json_boolean(value)
	if !ok {
		return false, format_error("UI tree field %q must be a boolean", name)
	}
	return flag, ""
}

@(private)
tree_number :: proc(object: json.Object, name: string) -> (f32, string) {
	value, has := json_get(object, name)
	if !has {
		return 0, format_error("UI tree field %q is missing", name)
	}
	number, ok := json_number(value)
	if !ok {
		return 0, format_error("UI tree field %q must be a number", name)
	}
	return f32(number), ""
}

@(private)
tree_int :: proc(object: json.Object, name: string) -> (int, string) {
	value, has := json_get(object, name)
	if !has {
		return 0, format_error("UI tree field %q is missing", name)
	}
	number, ok := json_integer(value)
	if !ok {
		return 0, format_error("UI tree field %q must be an integer", name)
	}
	return number, ""
}

@(private)
tree_vec4 :: proc(object: json.Object, name: string) -> ([4]f32, string) {
	value, has := json_get(object, name)
	if !has {
		return {}, format_error("UI tree field %q is missing", name)
	}
	array, ok := json_array(value)
	if !ok || len(array) != 4 {
		return {}, format_error("UI tree field %q must be four numbers", name)
	}
	result: [4]f32
	for element, index in array {
		number, number_ok := json_number(element)
		if !number_ok {
			return {}, format_error("UI tree field %q must be four numbers", name)
		}
		result[index] = f32(number)
	}
	return result, ""
}