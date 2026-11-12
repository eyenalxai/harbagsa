#+vet explicit-allocators
package platform

import "core:c"
import "core:log"
import "vendor:sdl3"

MAX_KEY_EDGES :: 16
MAX_UI_EVENTS :: 64

Key_Edge :: struct {
	key:  Key,
	mods: Modifiers,
}

UI_Input_Kind :: enum {
	Pointer_Move,
	Pointer_Down,
	Pointer_Up,
	Pointer_Leave,
	Wheel,
	Key_Down,
	Key_Up,
	Key_Repeat,
	Focus_Gained,
	Focus_Lost,
}

// One input event in arrival order. The collapsed fields below drive the game;
// this list drives the Rune view, which needs the order and each pointer point.
UI_Input_Event :: struct {
	kind:    UI_Input_Kind,
	pointer: [2]f32,
	wheel:   f32,
	key:     Key,
}

// One raw frame. It holds the held state, the pointer edges, the key edges, and
// the ordered UI events. The input module decides what a key means; platform
// does not.
Events :: struct {
	quit:    bool,
	resized: bool,

	move_forward: f32,
	move_right:   f32,
	sprint_held:  bool,
	fly_up:       bool,
	fly_down:     bool,

	look_delta:  [2]f32,
	wheel_delta: f32,

	pointer:      [2]f32,
	pointer_down: bool,

	primary_pressed:   bool,
	primary_released:  bool,
	secondary_pressed: bool,

	keys:      [MAX_KEY_EDGES]Key_Edge,
	key_count: int,

	ui_events:      [MAX_UI_EVENTS]UI_Input_Event,
	ui_event_count: int,

	captured: bool,
}

poll_events :: proc(window: ^Window) -> (events: Events) {
	return drain_events(window, nil)
}

wait_events :: proc(window: ^Window, timeout_ms: i32) -> (events: Events) {
	event: sdl3.Event
	if !sdl3.WaitEventTimeout(&event, timeout_ms) {
		return poll_events(window)
	}
	return drain_events(window, &event)
}

drain_events :: proc(window: ^Window, first: ^sdl3.Event) -> (events: Events) {
	events.captured = sdl3.GetWindowRelativeMouseMode(window.handle)
	if first != nil {
		apply_event(&events, first, window)
	}

	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		apply_event(&events, &event, window)
	}

	// Movement is polled with the cursor free too, so the debug camera can fly
	// while the palette holds the pointer.
	read_movement(&events)
	return
}

read_movement :: proc(events: ^Events) {
	key_count: c.int
	keys := sdl3.GetKeyboardState(&key_count)
	if keys == nil {
		return
	}

	if keys[int(sdl3.Scancode.W)] {
		events.move_forward += 1.0
	}
	if keys[int(sdl3.Scancode.S)] {
		events.move_forward -= 1.0
	}
	if keys[int(sdl3.Scancode.D)] {
		events.move_right += 1.0
	}
	if keys[int(sdl3.Scancode.A)] {
		events.move_right -= 1.0
	}
	events.sprint_held = keys[int(sdl3.Scancode.LSHIFT)]
	if keys[int(sdl3.Scancode.SPACE)] {
		events.fly_up = true
	}
	if keys[int(sdl3.Scancode.LCTRL)] || keys[int(sdl3.Scancode.RCTRL)] {
		events.fly_down = true
	}
}

apply_event :: proc(events: ^Events, event: ^sdl3.Event, window: ^Window) {
	#partial switch event.type {
	case .QUIT, .WINDOW_CLOSE_REQUESTED:
		events.quit = true
	case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
		events.resized = true
	case .MOUSE_BUTTON_DOWN:
		events.pointer = pointer_for(window, event.button.x, event.button.y)
		if event.button.button == sdl3.BUTTON_LEFT {
			push_ui_input(events, {kind = .Pointer_Move, pointer = events.pointer})
			push_ui_input(events, {kind = .Pointer_Down, pointer = events.pointer})
			if events.captured {
				events.primary_pressed = true
			} else {
				events.pointer_down = true
				if window.capture_on_click {
					events.captured = set_cursor_capture(window, true)
				}
			}
		} else if event.button.button == sdl3.BUTTON_RIGHT {
			events.secondary_pressed = true
		}
	case .MOUSE_BUTTON_UP:
		events.pointer = pointer_for(window, event.button.x, event.button.y)
		if event.button.button == sdl3.BUTTON_LEFT {
			push_ui_input(events, {kind = .Pointer_Move, pointer = events.pointer})
			push_ui_input(events, {kind = .Pointer_Up, pointer = events.pointer})
			events.primary_released = true
			events.pointer_down = false
		}
	case .MOUSE_WHEEL:
		push_ui_input(events, {
			kind = .Wheel,
			pointer = events.pointer,
			wheel = event.wheel.y,
		})
		events.wheel_delta += event.wheel.y
	case .KEY_DOWN:
		key := key_from_scancode(event.key.scancode)
		if key == .None {
			return
		}
		ui_kind := event.key.repeat ? UI_Input_Kind.Key_Repeat : UI_Input_Kind.Key_Down
		push_ui_input(events, {kind = ui_kind, key = key})
		if event.key.repeat {
			return
		}
		if events.key_count >= MAX_KEY_EDGES {
			log.warn("platform: the key edge buffer is full")
			return
		}
		events.keys[events.key_count] = {key, modifiers_from_sdl(event.key.mod)}
		events.key_count += 1
	case .KEY_UP:
		key := key_from_scancode(event.key.scancode)
		if key == .None {
			return
		}
		push_ui_input(events, {kind = .Key_Up, key = key})
	case .WINDOW_FOCUS_GAINED:
		push_ui_input(events, {kind = .Focus_Gained})
	case .WINDOW_FOCUS_LOST:
		push_ui_input(events, {kind = .Focus_Lost})
	case .WINDOW_MOUSE_LEAVE:
		push_ui_input(events, {kind = .Pointer_Leave})
	case .MOUSE_MOTION:
		events.pointer = pointer_for(window, event.motion.x, event.motion.y)
		push_ui_input(events, {kind = .Pointer_Move, pointer = events.pointer})
		if events.captured {
			events.look_delta.x += event.motion.xrel
			events.look_delta.y += event.motion.yrel
		}
	}
}

@(private)
push_ui_input :: proc(events: ^Events, event: UI_Input_Event) {
	if events.ui_event_count >= MAX_UI_EVENTS {
		log.warn("platform: the UI event buffer is full")
		return
	}
	events.ui_events[events.ui_event_count] = event
	events.ui_event_count += 1
}

@(private)
pointer_for :: proc(window: ^Window, x, y: f32) -> [2]f32 {
	width, height := window_size(window)
	return normalize_pointer(x, y, width, height)
}
