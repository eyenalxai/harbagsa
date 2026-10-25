#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

// The one tool that owns the input for this frame. The object palette, sun
// placement, and the placement tool are mutually exclusive. A caller reads the
// active tool from here; it does not re-derive the rule from three flags.
Active_Tool :: enum {
	None,
	Palette,
	Sun,
	Placement,
}

active_tool :: proc(dm: ^Debug_Mode) -> Active_Tool {
	if dm.palette.open {
		return .Palette
	}
	if dm.sun.active {
		return .Sun
	}
	if dm.placement.armed {
		return .Placement
	}
	return .None
}

// take_tool cancels every other tool. The caller enters the named tool with its
// own side effects: selecting a prefab, saving the sun position, or refreshing
// the ghost.
take_tool :: proc(dm: ^Debug_Mode, tool: Active_Tool) {
	if tool != .Palette {
		palette_close(&dm.palette)
	}
	if tool != .Sun {
		debug_sun_cancel(dm)
	}
	if tool != .Placement {
		debug_placement_cancel(dm)
	}
}
