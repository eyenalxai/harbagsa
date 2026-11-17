#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:input"
import "src:platform"
import "src:renderer"

Input_Snapshot_State :: struct {
	move_forward:   f32  `json:"move_forward"`,
	move_right:     f32  `json:"move_right"`,
	sprint_held:    bool `json:"sprint_held"`,
	sprint_pressed: bool `json:"sprint_pressed"`,
	jump_pressed:   bool `json:"jump_pressed"`,
}

Input_Vec2_State :: struct {
	x: f32 `json:"x"`,
	y: f32 `json:"y"`,
}

Input_Motion_State :: struct {
	move_forward: f32  `json:"move_forward"`,
	move_right:   f32  `json:"move_right"`,
	move_up:      f32  `json:"move_up"`,
	look:         Input_Vec2_State `json:"look"`,
	captured:     bool `json:"captured"`,
}

Input_View_State :: struct {
	debug_view:   bool `json:"debug_view"`,
	debug_mode:   bool `json:"debug_mode"`,
	taa:          bool `json:"taa"`,
	repro:        bool `json:"repro"`,
	reset_player: bool `json:"reset_player"`,
	reset_scene:  bool `json:"reset_scene"`,
	menu_toggle:  bool `json:"menu_toggle"`,
}

Input_Event_State :: struct {
	kind: string `json:"kind"`,
	sink: string `json:"sink"`,
	key:  string `json:"key,omitempty"`,
}

Input_Gamepad_State :: struct {
	connected: bool           `json:"connected"`,
	pressed:   []string       `json:"pressed"`,
	released:  []string       `json:"released"`,
	left:      Input_Vec2_State `json:"left"`,
	right:     Input_Vec2_State `json:"right"`,
}

// Input_State is the resolved intent of the last frame and the route that
// produced it. A scenario asserts the sink of a raw event here.
Input_State :: struct {
	owner:    string              `json:"owner"`,
	captured: bool                `json:"captured"`,
	overflow: bool                `json:"overflow"`,
	snapshot: Input_Snapshot_State `json:"snapshot"`,
	look:     Input_Vec2_State    `json:"look"`,
	motion:   Input_Motion_State  `json:"motion"`,
	view:     Input_View_State    `json:"view"`,
	actions:  []string            `json:"actions"`,
	events:   []Input_Event_State `json:"events"`,
	gamepad:  Input_Gamepad_State `json:"gamepad"`,
}

Input_Observation :: struct {
	routed:     input.Routed_Frame,
	has_routed: bool,
	captured:   bool,
	ui_events:  []renderer.UI_Event,
	gamepad:    platform.Gamepad_State,
}

build_state_input :: proc(state: ^State, ctx: ^State_Context) {
	observation := ctx.input
	if !observation.has_routed {
		state.input = {
			owner = "world",
			gamepad = input_gamepad_state(observation.gamepad, ctx.allocator),
		}
		return
	}
	routed := observation.routed
	state.input = {
		owner    = owner_name(routed.owner),
		captured = observation.captured,
		overflow = routed.overflow,
		snapshot = {
			move_forward   = routed.game.snapshot.move_forward,
			move_right     = routed.game.snapshot.move_right,
			sprint_held    = routed.game.snapshot.sprint_held,
			sprint_pressed = routed.game.snapshot.sprint_pressed,
			jump_pressed   = routed.game.snapshot.jump_pressed,
		},
		look = {x = routed.game.look_delta.x, y = routed.game.look_delta.y},
		motion = {
			move_forward = routed.game.motion.move_forward,
			move_right   = routed.game.motion.move_right,
			move_up      = routed.game.motion.move_up,
			look         = {
				x = routed.game.motion.look_delta.x,
				y = routed.game.motion.look_delta.y,
			},
			captured = routed.game.motion.captured,
		},
		view = {
			debug_view   = routed.game.view.debug_view,
			debug_mode   = routed.game.view.debug_mode,
			taa          = routed.game.view.taa,
			repro        = routed.game.view.repro,
			reset_player = routed.game.view.reset_player,
			reset_scene  = routed.game.view.reset_scene,
			menu_toggle  = routed.game.view.menu_toggle,
		},
		gamepad = input_gamepad_state(observation.gamepad, ctx.allocator),
	}
	if routed.game.action_count > 0 {
		state.input.actions = make([]string, routed.game.action_count, ctx.allocator)
		for action, index in routed.game.actions[:routed.game.action_count] {
			state.input.actions[index] = edit_action_name(action)
		}
	}
	if routed.event_count > 0 {
		state.input.events = make([]Input_Event_State, routed.event_count, ctx.allocator)
		for index in 0 ..< routed.event_count {
			event := routed.events[index]
			entry := Input_Event_State {
				kind = input_kind_name(event.kind),
				sink = sink_name(routed.event_sinks[index]),
			}
			if event.key != .None {
				entry.key = key_name(event.key)
			}
			state.input.events[index] = entry
		}
	}
}

@(private)
input_gamepad_state :: proc(
	pad: platform.Gamepad_State,
	allocator: mem.Allocator,
) -> Input_Gamepad_State {
	result := Input_Gamepad_State {
		connected = pad.connected,
		left      = {x = pad.left.x, y = pad.left.y},
		right     = {x = pad.right.x, y = pad.right.y},
	}
	pressed := make([dynamic]string, 0, len(platform.Gamepad_Button), allocator)
	released := make([dynamic]string, 0, len(platform.Gamepad_Button), allocator)
	for button in platform.Gamepad_Button {
		if button in pad.pressed {
			append(&pressed, strings.clone(gamepad_button_name(button), allocator))
		}
		if button in pad.released {
			append(&released, strings.clone(gamepad_button_name(button), allocator))
		}
	}
	result.pressed = pressed[:]
	result.released = released[:]
	return result
}

input_state_destroy :: proc(state: ^Input_State, allocator: mem.Allocator) {
	if state.actions != nil {
		delete(state.actions, allocator)
	}
	if state.events != nil {
		delete(state.events, allocator)
	}
	if state.gamepad.pressed != nil {
		for name in state.gamepad.pressed {
			delete(name, allocator)
		}
		delete(state.gamepad.pressed, allocator)
	}
	if state.gamepad.released != nil {
		for name in state.gamepad.released {
			delete(name, allocator)
		}
		delete(state.gamepad.released, allocator)
	}
	state^ = {}
}
