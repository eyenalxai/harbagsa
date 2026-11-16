#+vet explicit-allocators
package platform

import "core:c"
import "core:log"
import "vendor:sdl3"

MAX_KEY_EVENTS :: 32
MAX_INPUT_EVENTS :: 64

Key_Event :: struct {
	kind: Input_Kind,
	key:  Key,
	mods: Modifiers,
}

Input_Kind :: enum {
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

// One raw event in arrival order. The input module routes every event to
// exactly one sink; the platform never decides what a key or button means.
Input_Event :: struct {
	kind:    Input_Kind,
	pointer: [2]f32,
	wheel:   f32,
	key:     Key,
	mods:    Modifiers,
}

// One raw frame: the ordered events, the held movement axes, and the first
// gamepad's state. It holds no resolved intent.
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

	pointer:           [2]f32,
	primary_pressed:   bool,
	primary_released:  bool,
	secondary_pressed: bool,

	raw:       [MAX_INPUT_EVENTS]Input_Event,
	raw_count: int,
	overflow:  bool,

	gamepad: Gamepad_State,

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
	// with the keyboard while the palette holds the pointer.
	read_movement(&events)
	gamepad_read(&window.gamepad, &events.gamepad)
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
			push_input(events, {kind = .Pointer_Move, pointer = events.pointer})
			push_input(events, {kind = .Pointer_Down, pointer = events.pointer})
			if events.captured {
				events.primary_pressed = true
			} else if window.capture_on_click {
				events.captured = set_cursor_capture(window, true)
			}
		} else if event.button.button == sdl3.BUTTON_RIGHT {
			events.secondary_pressed = true
		}
	case .MOUSE_BUTTON_UP:
		events.pointer = pointer_for(window, event.button.x, event.button.y)
		if event.button.button == sdl3.BUTTON_LEFT {
			push_input(events, {kind = .Pointer_Move, pointer = events.pointer})
			push_input(events, {kind = .Pointer_Up, pointer = events.pointer})
			events.primary_released = true
		}
	case .MOUSE_WHEEL:
		push_input(events, {
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
		kind := event.key.repeat ? Input_Kind.Key_Repeat : Input_Kind.Key_Down
		push_input(events, {
			kind = kind,
			key = key,
			mods = modifiers_from_sdl(event.key.mod),
		})
	case .KEY_UP:
		key := key_from_scancode(event.key.scancode)
		if key == .None {
			return
		}
		push_input(events, {
			kind = .Key_Up,
			key = key,
			mods = modifiers_from_sdl(event.key.mod),
		})
	case .GAMEPAD_BUTTON_DOWN, .GAMEPAD_BUTTON_UP:
		if window.gamepad.handle == nil {
			return
		}
		if event.gbutton.which != sdl3.GetGamepadID(window.gamepad.handle) {
			return
		}
		button, ok := gamepad_button_from_sdl(sdl3.GamepadButton(event.gbutton.button))
		if !ok {
			return
		}
		gamepad_button_event(&window.gamepad, &events.gamepad, button, event.gbutton.down)
	case .WINDOW_FOCUS_GAINED:
		push_input(events, {kind = .Focus_Gained})
	case .WINDOW_FOCUS_LOST:
		push_input(events, {kind = .Focus_Lost})
	case .WINDOW_MOUSE_LEAVE:
		push_input(events, {kind = .Pointer_Leave})
	case .MOUSE_MOTION:
		events.pointer = pointer_for(window, event.motion.x, event.motion.y)
		push_input(events, {kind = .Pointer_Move, pointer = events.pointer})
		if events.captured {
			events.look_delta.x += event.motion.xrel
			events.look_delta.y += event.motion.yrel
		}
	}
}

@(private)
push_input :: proc(events: ^Events, event: Input_Event) {
	if events.raw_count >= MAX_INPUT_EVENTS {
		events.overflow = true
		log.warn("platform: the input event buffer is full")
		return
	}
	events.raw[events.raw_count] = event
	events.raw_count += 1
}

@(private)
pointer_for :: proc(window: ^Window, x, y: f32) -> [2]f32 {
	width, height := window_size(window)
	return normalize_pointer(x, y, width, height)
}
