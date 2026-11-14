#+vet explicit-allocators
package harness

import "core:mem"

import "src:renderer"

Ui_Tree_Node :: struct {
	path:          string `json:"path"`,
	key:           string `json:"key,omitempty"`,
	role:          string `json:"role"`,
	label:         string `json:"label,omitempty"`,
	text:          string `json:"text,omitempty"`,
	focused:       bool   `json:"focused"`,
	focus_visible: bool   `json:"focus_visible"`,
	selected:      bool   `json:"selected"`,
	hover:         f32    `json:"hover"`,
	press:         f32    `json:"press"`,
	opacity:       f32    `json:"opacity"`,
	rect:          [4]f32 `json:"rect"`,
	target:        [4]f32 `json:"target"`,
	parent:        int    `json:"parent"`,
}

ui_run_reset :: proc(session: ^Session, allocator: mem.Allocator) {
	clear(&session.ui_actions)
	ui_tree_destroy(session, allocator)
}

ui_run_destroy :: proc(session: ^Session, allocator: mem.Allocator) {
	ui_run_reset(session, allocator)
	delete(session.ui_actions)
	session.ui_actions = nil
}

session_ui_set_tree :: proc(session: ^Session, tree: []Ui_Tree_Node) {
	ui_tree_destroy(session, session.allocator)
	session.ui_tree = tree
	session.has_ui_tree = tree != nil
}

session_ui_observation :: proc(session: ^Session) -> (Ui_Observation, string) {
	observation := Ui_Observation{actions = session.ui_actions[:]}
	if session.render.backend == nil {
		return observation, ""
	}
	interaction, ok := renderer.ui_query_interaction()
	if !ok {
		return observation, format_error("%s", "the UI shim did not report its interaction state")
	}
	observation.interaction = interaction
	observation.has_interaction = true
	return observation, ""
}

@(private)
ui_tree_destroy :: proc(session: ^Session, allocator: mem.Allocator) {
	ui_tree_nodes_destroy(session.ui_tree, allocator)
	session.ui_tree = nil
	session.has_ui_tree = false
}

ui_tree_nodes_destroy :: proc(nodes: []Ui_Tree_Node, allocator: mem.Allocator) {
	for &node in nodes {
		free_owned_string(&node.path, allocator)
		free_owned_string(&node.key, allocator)
		free_owned_string(&node.role, allocator)
		free_owned_string(&node.label, allocator)
		free_owned_string(&node.text, allocator)
	}
	if nodes != nil {
		delete(nodes, allocator)
	}
}

free_owned_string :: proc(text: ^string, allocator: mem.Allocator) {
	if text^ != "" {
		delete(text^, allocator)
		text^ = ""
	}
}