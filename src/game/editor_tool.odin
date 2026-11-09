#+vet explicit-allocators
#+vet !unused-procedures // the agent harness reads the tool kind name; the game binary does not
package game

// One tool owns the frame. The palette and placement payloads live in the active
// variant, so only one can exist and there is no separate open or armed flag.
Tool_None :: struct {}

Palette :: struct {
	selected:  Prefab_Id,
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

Tool_Kind :: enum {
	None,
	Palette,
	Placement,
}

Tool :: union #no_nil {
	Tool_None,
	Palette,
	Placement,
}

TOOL_KIND_NAMES := [Tool_Kind]string {
	.None = "none",
	.Palette = "palette",
	.Placement = "placement",
}

tool_kind_name :: proc(kind: Tool_Kind) -> string {
	return TOOL_KIND_NAMES[kind]
}

tool_kind :: proc(tool: Tool) -> Tool_Kind {
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
