#+vet explicit-allocators
#+vet !unused-procedures // the window loop calls this API; the game binary does not
package input

import "core:log"
import "core:math"

import "src:game"
import "src:platform"

// resolve turns one raw platform frame into one intent. The order is the rule:
// menu, then tool, then world. Nothing in here allocates.
resolve :: proc(
	r: ^Resolver,
	events: platform.Events,
	focus: Focus,
) -> Frame_Input {
	out := Frame_Input {
		pause = focus.game.menu_open,
	}

	// A pause or a free cursor drops every latch, so a press never queues
	// through the menu or a released pointer.
	if focus.game.menu_open || !focus.captured || focus.game.editor.active {
		clear_latches(r)
	}

	if focus.game.menu_open {
		for index in 0 ..< events.key_count {
			apply_menu_key(&out, events.keys[index])
		}
		return out
	}

	// The tool that owns this frame's pointer can change during the frame (Tab,
	// Enter, and Esc), so the pointer route tracks it as the keys apply.
	state := Key_State {
		pointer_tool = focus.game.editor.tool,
	}
	for index in 0 ..< events.key_count {
		apply_key(r, &out, &state, events.keys[index], focus)
	}

	out.motion = {
		move_forward = events.move_forward,
		move_right   = events.move_right,
		move_up      = (events.fly_up ? 1.0 : 0.0) - (events.fly_down ? 1.0 : 0.0),
		look_delta   = events.look_delta,
		captured     = focus.captured,
	}

	if focus.game.editor.active {
		apply_debug_pointer(&out, events, focus, &state)
		return out
	}

	out.look_delta = focus.captured ? events.look_delta : {}
	out.snapshot = {
		move_forward   = focus.captured ? events.move_forward : 0,
		move_right     = focus.captured ? events.move_right : 0,
		sprint_held    = focus.captured && events.sprint_held,
		sprint_pressed = r.sprint,
		jump_pressed   = r.jump,
	}
	return out
}

@(private)
Key_State :: struct {
	pointer_tool: game.Tool_Kind,
}

@(private)
apply_key :: proc(
	r: ^Resolver,
	out: ^Frame_Input,
	state: ^Key_State,
	edge: platform.Key_Edge,
	focus: Focus,
) {
	// The old handlers ran the palette block before the light keys, then the
	// world keys. Tab, Esc, M, and G ran before that gate.
	editing := state.pointer_tool != .Palette
	#partial switch edge.key {
	case .Escape:
		if focus.game.editor.active && focus.game.editor.tool != .None {
			add_action(out, game.Cancel{})
		} else {
			out.view.menu_toggle = true
		}
	case .Tab:
		if focus.game.editor.active {
			if state.pointer_tool == .Palette {
				add_action(out, game.Palette_Close{})
				state.pointer_tool = .None
			} else if state.pointer_tool != .Placement {
				add_action(out, game.Palette_Open{})
				state.pointer_tool = .Palette
			}
		}
	case .Up, .Down, .Left, .Right, .Enter:
		if state.pointer_tool == .Palette {
			apply_palette_navigation(out, state, edge)
		}
	case .Digit_1, .Digit_2, .Digit_3, .Digit_4, .Digit_5, .Digit_6, .Digit_7, .Digit_8, .Digit_9:
		if focus.game.editor.active && state.pointer_tool == .Palette {
			index := int(edge.key) - int(platform.Key.Digit_1)
			add_action(out, game.Palette_Select{index = index})
		}
	case .M:
		if focus.game.editor.active {
			add_action(out, game.Flip_Body{})
		}
	case .G:
		if focus.game.editor.active {
			add_action(out, game.Placement_Toggle_Snap{})
		}
	case .Q:
		if focus.game.editor.active && editing {
			add_action(out, game.Turn{steps = -1, large = .Shift in edge.mods})
		}
	case .E:
		if focus.game.editor.active && editing {
			add_action(out, game.Turn{steps = 1, large = .Shift in edge.mods})
		}
	case .C:
		if focus.game.editor.active {
			add_action(out, game.Light_Adjust{change = .Color})
		}
	case .K:
		if focus.game.editor.active {
			add_action(out, game.Light_Toggle_Kind{})
		}
	case .Left_Bracket:
		if focus.game.editor.active {
			add_action(out, game.Light_Adjust{change = .Intensity_Down})
		}
	case .Right_Bracket:
		if focus.game.editor.active {
			add_action(out, game.Light_Adjust{change = .Intensity_Up})
		}
	case .Comma:
		if focus.game.editor.active {
			add_action(out, game.Light_Adjust{change = .Range_Down})
		}
	case .Period:
		if focus.game.editor.active {
			add_action(out, game.Light_Adjust{change = .Range_Up})
		}
	case .Delete, .X:
		if focus.game.editor.active && editing {
			add_action(out, game.Delete_Selected{})
		}
	case .D:
		if focus.game.editor.active && editing && .Ctrl in edge.mods {
			add_action(out, game.Duplicate_Selected{})
		}
	case .Z:
		if focus.game.editor.active {
			if editing && .Ctrl in edge.mods {
				if .Shift in edge.mods {
					add_action(out, game.Redo{})
				} else {
					add_action(out, game.Undo{})
				}
			}
		}
	case .Space:
		if !focus.game.editor.active && focus.captured {
			r.jump = true
		}
	case .LShift:
		if !focus.game.editor.active && focus.captured {
			r.sprint = true
		}
	case .R:
		if .Shift in edge.mods {
			out.view.reset_scene = true
		} else {
			out.view.reset_player = true
		}
	case .F1:
		out.view.debug_view = true
	case .F2:
		out.view.debug_mode = true
	case .F3:
		out.view.taa = true
	case .F5:
		out.view.repro = true
	}
}

@(private)
apply_menu_key :: proc(out: ^Frame_Input, edge: platform.Key_Edge) {
	#partial switch edge.key {
	case .Escape:
		out.view.menu_toggle = true
	case .Up:
		out.menu.up = true
	case .Down:
		out.menu.down = true
	case .Left:
		out.menu.left = true
	case .Right:
		out.menu.right = true
	case .Enter:
		out.menu.confirm = true
	}
}

@(private)
apply_palette_navigation :: proc(
	out: ^Frame_Input,
	state: ^Key_State,
	edge: platform.Key_Edge,
) {
	#partial switch edge.key {
	case .Up, .Left:
		add_action(out, game.Palette_Step{delta = -1})
	case .Down, .Right:
		add_action(out, game.Palette_Step{delta = 1})
	case .Enter:
		add_action(out, game.Palette_Pick{})
		state.pointer_tool = .None
	}
}

@(private)
apply_debug_pointer :: proc(
	out: ^Frame_Input,
	events: platform.Events,
	focus: Focus,
	state: ^Key_State,
) {
	if state.pointer_tool == .Palette {
		// Rune owns the pointer while the palette is open; the row press returns
		// a flat action and the game applies it after the draw.
		return
	}
	switch state.pointer_tool {
	case .Placement, .None:
		apply_world_pointer(out, events, focus)
	case .Palette:
	}
}

@(private)
apply_world_pointer :: proc(out: ^Frame_Input, events: platform.Events, focus: Focus) {
	if events.primary_pressed {
		add_action(out, game.Primary_Press{})
	}
	if events.primary_released {
		add_action(out, game.Primary_Release{})
	}
	if events.secondary_pressed {
		add_action(out, game.Secondary_Press{})
	}
	if events.wheel_delta != 0.0 {
		add_action(
			out,
			game.Wheel {
				steps = int(math.round(events.wheel_delta)),
				large = events.sprint_held,
			},
		)
	}
	if focus.game.editor.dragging {
		add_action(out, game.Drag_Move{look_delta = events.look_delta})
	}
}

@(private)
add_action :: proc(out: ^Frame_Input, action: game.Edit_Action) {
	if out.action_count >= game.MAX_EDIT_ACTIONS {
		log.warn("input: the frame action buffer is full")
		return
	}
	out.actions[out.action_count] = action
	out.action_count += 1
}
