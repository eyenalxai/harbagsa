#+vet explicit-allocators
#+vet !unused-procedures // the window loop calls this API; the game binary does not
package input

import "core:log"
import "core:math"

import "src:game"
import "src:platform"

// resolve turns one routed key list into one game intent. The order is the
// rule: inspector, then tool, then world. Nothing in here allocates.
resolve :: proc(
	r: ^Resolver,
	events: platform.Events,
	keys: []platform.Key_Event,
	focus: game.Focus,
	owner: Owner,
) -> Frame_Input {
	out := Frame_Input{}
	captured := events.captured

	// A pause or a free cursor drops every latch, so a press never queues
	// through the menu or a released pointer.
	if focus.menu_open || !captured || focus.editor.active {
		clear_latches(r)
	}

	// The owner and the tool that owns this frame's pointer can change during
	// the frame (I, Tab, Enter, and Esc), so the key route tracks them as keys
	// apply.
	state := Key_State {
		pointer_tool = focus.editor.tool,
		owner        = owner,
	}
	for edge in keys {
		if edge.kind == .Key_Down {
			apply_key(r, &out, &state, edge, focus, captured)
		}
	}

	out.motion = {
		move_forward = events.move_forward,
		move_right   = events.move_right,
		move_up      = (events.fly_up ? 1.0 : 0.0) - (events.fly_down ? 1.0 : 0.0),
		look_delta   = events.look_delta,
		captured     = captured,
	}

	if state.owner == .Inspector {
		out.motion = {}
		return out
	}
	if focus.editor.active {
		apply_debug_pointer(&out, events, focus, &state)
		return out
	}

	out.look_delta = captured ? events.look_delta : {}
	out.snapshot = {
		move_forward   = captured ? events.move_forward : 0,
		move_right     = captured ? events.move_right : 0,
		sprint_held    = captured && events.sprint_held,
		sprint_pressed = r.sprint,
		jump_pressed   = r.jump,
	}
	return out
}

@(private)
Key_State :: struct {
	pointer_tool: game.Tool_Kind,
	owner:        Owner,
}

@(private)
editor_owner :: proc(focus: game.Focus) -> Owner {
	return focus.editor.active ? .Placement : .World
}

@(private)
apply_key :: proc(
	r: ^Resolver,
	out: ^Frame_Input,
	state: ^Key_State,
	edge: platform.Key_Event,
	focus: game.Focus,
	captured: bool,
) {
	if state.owner == .Inspector {
		#partial switch edge.key {
		case .Escape:
			add_action(out, game.Inspector_Close{})
			state.owner = editor_owner(focus)
		case .I:
			add_action(out, game.Inspector_Toggle{})
			state.owner = editor_owner(focus)
		}
		return
	}
	if state.owner == .Menu {
		return
	}

	editing := state.pointer_tool != .Palette
	#partial switch edge.key {
	case .Escape:
		if focus.editor.active && state.pointer_tool != .None {
			add_action(out, game.Cancel{})
			state.pointer_tool = .None
			state.owner = .Placement
		} else {
			out.view.menu_toggle = true
			state.owner = .Menu
		}
	case .I:
		if focus.editor.active {
			add_action(out, game.Inspector_Toggle{})
			state.pointer_tool = .None
			state.owner = .Inspector
		}
	case .Tab:
		if focus.editor.active {
			if state.pointer_tool == .Palette {
				add_action(out, game.Palette_Close{})
				state.pointer_tool = .None
				state.owner = .Placement
			} else if state.pointer_tool != .Placement {
				add_action(out, game.Palette_Open{})
				state.pointer_tool = .Palette
				state.owner = .Palette
			}
		}
	case .Up, .Down, .Left, .Right, .Enter:
		if state.pointer_tool == .Palette {
			apply_palette_navigation(out, state, edge)
		}
	case .Digit_1, .Digit_2, .Digit_3, .Digit_4, .Digit_5, .Digit_6, .Digit_7, .Digit_8, .Digit_9:
		if focus.editor.active && state.pointer_tool == .Palette {
			index := int(edge.key) - int(platform.Key.Digit_1)
			add_action(out, game.Palette_Select{index = index})
		}
	case .M:
		if focus.editor.active {
			add_action(out, game.Flip_Body{})
		}
	case .G:
		if focus.editor.active {
			add_action(out, game.Placement_Toggle_Snap{})
		}
	case .Q:
		if focus.editor.active && editing {
			add_action(out, game.Turn{steps = -1, large = .Shift in edge.mods})
		}
	case .E:
		if focus.editor.active && editing {
			add_action(out, game.Turn{steps = 1, large = .Shift in edge.mods})
		}
	case .C:
		if focus.editor.active {
			add_action(out, game.Light_Adjust{change = .Color})
		}
	case .K:
		if focus.editor.active {
			add_action(out, game.Light_Toggle_Kind{})
		}
	case .Left_Bracket:
		if focus.editor.active {
			add_action(out, game.Light_Adjust{change = .Intensity_Down})
		}
	case .Right_Bracket:
		if focus.editor.active {
			add_action(out, game.Light_Adjust{change = .Intensity_Up})
		}
	case .Comma:
		if focus.editor.active {
			add_action(out, game.Light_Adjust{change = .Range_Down})
		}
	case .Period:
		if focus.editor.active {
			add_action(out, game.Light_Adjust{change = .Range_Up})
		}
	case .Delete, .X:
		if focus.editor.active && editing {
			add_action(out, game.Delete_Selected{})
		}
	case .D:
		if focus.editor.active && editing && .Ctrl in edge.mods {
			add_action(out, game.Duplicate_Selected{})
		}
	case .Z:
		if focus.editor.active {
			if editing && .Ctrl in edge.mods {
				if .Shift in edge.mods {
					add_action(out, game.Redo{})
				} else {
					add_action(out, game.Undo{})
				}
			}
		}
	case .Space:
		if !focus.editor.active && captured {
			r.jump = true
		}
	case .LShift:
		if !focus.editor.active && captured {
			r.sprint = true
		}
	case .R:
		if .Shift in edge.mods {
			out.view.reset_scene = true
		} else {
			out.view.reset_player = true
		}
	case .F1, .F2, .F3, .F5:
		if exact_chord(edge.mods) {
			#partial switch edge.key {
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
	}
}

@(private)
exact_chord :: proc(mods: platform.Modifiers) -> bool {
	return .Ctrl in mods && .Shift in mods && card(mods) == 2
}

@(private)
apply_palette_navigation :: proc(
	out: ^Frame_Input,
	state: ^Key_State,
	edge: platform.Key_Event,
) {
	#partial switch edge.key {
	case .Up, .Left:
		add_action(out, game.Palette_Step{delta = -1})
	case .Down, .Right:
		add_action(out, game.Palette_Step{delta = 1})
	case .Enter:
		add_action(out, game.Palette_Pick{})
		state.pointer_tool = .None
		state.owner = .Placement
	}
}

@(private)
apply_debug_pointer :: proc(
	out: ^Frame_Input,
	events: platform.Events,
	focus: game.Focus,
	state: ^Key_State,
) {
	if state.pointer_tool != .Palette {
		apply_world_pointer(out, events, focus)
	}
}

@(private)
apply_world_pointer :: proc(out: ^Frame_Input, events: platform.Events, focus: game.Focus) {
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
	if focus.editor.dragging {
		add_action(out, game.Drag_Move{look_delta = events.look_delta})
	}
}

@(private)
add_action :: proc(out: ^Frame_Input, action: game.Edit_Action) {
	if out.action_count >= game.MAX_EDIT_ACTIONS {
		out.overflow = true
		log.warn("input: the frame action buffer is full")
		return
	}
	out.actions[out.action_count] = action
	out.action_count += 1
}
