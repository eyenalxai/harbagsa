#+vet explicit-allocators
package platform

import "core:c"
import "vendor:sdl3"

MAX_KEY_EDGES :: 16

Key_Edge :: struct {
	key:  Key,
	mods: Modifiers,
}

// One raw frame. It holds the held state, the pointer edges, and the key-down
// edges. The input module decides what a key means; platform does not.
Events :: struct {
	quit:    bool,
	resized: bool,

	move_forward: f32,
	move_right:   f32,
	sprint_held:  bool,
	crouch_held:  bool,
	prone_held:   bool,
	jump_held:    bool,
	fly_up:       bool,
	fly_down:     bool,

	look_delta:  [2]f32,
	wheel_delta: f32,

	pointer:         [2]f32,
	pointer_down:    bool,
	pointer_moved:   bool,
	pointer_pressed: bool,

	primary_pressed:   bool,
	primary_released:  bool,
	secondary_pressed: bool,

	keys:      [MAX_KEY_EDGES]Key_Edge,
	key_count: int,

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
	events.crouch_held = keys[int(sdl3.Scancode.C)]
	events.prone_held = keys[int(sdl3.Scancode.Z)]
	events.jump_held = keys[int(sdl3.Scancode.SPACE)]
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
			if events.captured {
				events.primary_pressed = true
			} else {
				events.pointer_pressed = true
				events.pointer_down = true
				if window.capture_on_click {
					events.captured = set_cursor_capture(window, true)
				}
			}
		} else if event.button.button == sdl3.BUTTON_RIGHT {
			events.secondary_pressed = true
		}
	case .MOUSE_BUTTON_UP:
		if event.button.button == sdl3.BUTTON_LEFT {
			events.primary_released = true
			events.pointer_down = false
		}
	case .MOUSE_WHEEL:
		if events.captured {
			events.wheel_delta += event.wheel.y
		}
	case .KEY_DOWN:
		if event.key.repeat {
			return
		}
		key := key_from_scancode(event.key.scancode)
		if key == .None || events.key_count >= MAX_KEY_EDGES {
			return
		}
		events.keys[events.key_count] = {key, modifiers_from_sdl(event.key.mod)}
		events.key_count += 1
	case .MOUSE_MOTION:
		events.pointer = pointer_for(window, event.motion.x, event.motion.y)
		events.pointer_moved = true
		if events.captured {
			events.look_delta.x += event.motion.xrel
			events.look_delta.y += event.motion.yrel
		}
	}
}

@(private)
pointer_for :: proc(window: ^Window, x, y: f32) -> [2]f32 {
	width, height := window_size(window)
	return normalize_pointer(x, y, width, height)
}
