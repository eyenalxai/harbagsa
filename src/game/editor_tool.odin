#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

// One tool owns the frame. The palette and placement payloads live in the active
// variant, so only one can exist and there is no separate open or armed flag.
Tool_None :: struct {}

Palette :: struct {
	selected:  int,
	body_mode: Body_Mode,
	light:     Light_Settings,
}

Placement :: struct {
	prefab:      Prefab_Id,
	height:      f32,
	yaw_degrees: f32,
	snap:        bool,
	body_mode:   Body_Mode,
	light:       Light_Settings,
}

Editor_Tool :: enum {
	None,
	Palette,
	Placement,
}

Tool :: union #no_nil {
	Tool_None,
	Palette,
	Placement,
}

EDITOR_TOOL_NAMES := [Editor_Tool]string {
	.None = "none",
	.Palette = "palette",
	.Placement = "placement",
}

editor_tool_name :: proc(tool: Editor_Tool) -> string {
	return EDITOR_TOOL_NAMES[tool]
}

editor_tool_kind :: proc(tool: Tool) -> Editor_Tool {
	switch _ in tool {
	case Tool_None:
		return .None
	case Palette:
		return .Palette
	case Placement:
		return .Placement
	}
	return .None
}
