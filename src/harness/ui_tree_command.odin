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
	path, has_path := tree_string(object, "path")
	if !has_path || path == "" {
		return {}, format_error("%s", "a UI tree element has no path")
	}
	node := Ui_Tree_Node {
		path          = strings.clone(path, allocator),
		key           = clone_tree_text(tree_optional_string(object, "key"), allocator),
		role          = clone_tree_text(tree_optional_string(object, "role"), allocator),
		label         = clone_tree_text(tree_optional_string(object, "label"), allocator),
		text          = clone_tree_text(tree_optional_string(object, "text"), allocator),
		focused       = tree_bool(object, "focused"),
		focus_visible = tree_bool(object, "focus_visible"),
		selected      = tree_bool(object, "selected"),
		hover         = tree_number(object, "hover"),
		press         = tree_number(object, "press"),
		opacity       = tree_number(object, "opacity"),
		rect          = tree_vec4(object, "rect"),
		target        = tree_vec4(object, "target"),
		parent        = tree_int(object, "parent", -1),
	}
	return node, ""
}

@(private)
tree_string :: proc(object: json.Object, name: string) -> (string, bool) {
	value, has := json_get(object, name)
	if !has {
		return "", false
	}
	return json_string(value)
}

@(private)
tree_optional_string :: proc(object: json.Object, name: string) -> string {
	value, has := json_get(object, name)
	if !has || json_is_null(value) {
		return ""
	}
	text, ok := json_string(value)
	return ok ? text : ""
}

@(private)
tree_bool :: proc(object: json.Object, name: string) -> bool {
	value, has := json_get(object, name)
	if !has {
		return false
	}
	flag, ok := json_boolean(value)
	return ok && flag
}

@(private)
tree_number :: proc(object: json.Object, name: string) -> f32 {
	value, has := json_get(object, name)
	if !has {
		return 0
	}
	number, ok := json_number(value)
	return ok ? f32(number) : 0
}

@(private)
tree_int :: proc(object: json.Object, name: string, fallback: int) -> int {
	value, has := json_get(object, name)
	if !has {
		return fallback
	}
	number, ok := json_integer(value)
	return ok ? number : fallback
}

@(private)
tree_vec4 :: proc(object: json.Object, name: string) -> [4]f32 {
	value, has := json_get(object, name)
	if !has {
		return {}
	}
	array, ok := json_array(value)
	if !ok || len(array) != 4 {
		return {}
	}
	result: [4]f32
	for element, index in array {
		number, number_ok := json_number(element)
		if !number_ok {
			return {}
		}
		result[index] = f32(number)
	}
	return result
}
