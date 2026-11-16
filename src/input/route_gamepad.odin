#+vet explicit-allocators
#+vet !unused-procedures // the window loop calls this API; the game binary does not
package input

import "core:math"

import "src:platform"

GAMEPAD_LOOK_PER_FRAME :: f32(8.0)
GAMEPAD_STICK_PRESS :: f32(0.5)
GAMEPAD_STICK_RELEASE :: f32(0.4)

@(private)
route_gamepad :: proc(
	r: ^Resolver,
	out: ^Routed_Frame,
	pad: platform.Gamepad_State,
	keys: ^[platform.MAX_KEY_EVENTS]platform.Key_Event,
	key_count: ^int,
) -> (
	primary_pressed: bool,
	primary_released: bool,
	menu_toggle: bool,
) {
	if !pad.connected {
		if r.pad_primary {
			r.pad_primary = false
			primary_released = true
		}
		release_gamepad(r, out, keys, key_count)
		return
	}

	route_gamepad_buttons(r, out, pad, keys, key_count)
	route_gamepad_stick(r, out, pad.left, out.owner, keys, key_count)

	if out.owner == .Placement && .South in pad.pressed {
		r.pad_primary = true
		primary_pressed = true
	}
	if .South in pad.released && r.pad_primary {
		r.pad_primary = false
		primary_released = true
	}
	if out.owner != .Menu && .Start in pad.pressed {
		menu_toggle = true
	}
	return
}

@(private)
route_gamepad_buttons :: proc(
	r: ^Resolver,
	out: ^Routed_Frame,
	pad: platform.Gamepad_State,
	keys: ^[platform.MAX_KEY_EVENTS]platform.Key_Event,
	key_count: ^int,
) {
	for button in platform.Gamepad_Button {
		if button in pad.pressed {
			key, mods, mapped := gamepad_key(out.owner, button)
			if mapped {
				sink := key_sink_for(out.owner, key)
				r.buttons[button] = {key = key, sink = sink}
				if press_key(r, sink, key) {
					route_event(out, sink, .Key_Down, key, mods, keys, key_count)
				}
			} else {
				r.buttons[button] = {}
			}
		}
		if button in pad.released {
			held := r.buttons[button]
			if held.key != .None && held.sink != .None && release_key(r, held.sink, held.key) {
				route_event(out, held.sink, .Key_Up, held.key, {}, keys, key_count)
			}
			r.buttons[button] = {}
		}
	}
}

// gamepad_key maps the pad to the same key vocabulary the keyboard uses. The UI
// never sees a gamepad type; it receives a normalized key event at the ABI.
@(private)
gamepad_key :: proc(
	owner: Owner,
	button: platform.Gamepad_Button,
) -> (
	key: platform.Key,
	mods: platform.Modifiers,
	mapped: bool,
) {
	switch owner {
	case .Menu, .Inspector:
		#partial switch button {
		case .Dpad_Up:
			return .Up, {}, true
		case .Dpad_Down:
			return .Down, {}, true
		case .Dpad_Left:
			return .Left, {}, true
		case .Dpad_Right:
			return .Right, {}, true
		case .South:
			return .Enter, {}, true
		case .East:
			return .Escape, {}, true
		case .Left_Shoulder:
			return .Tab, {.Shift}, true
		case .Right_Shoulder:
			return .Tab, {}, true
		case .Start:
			if owner == .Menu {
				return .Escape, {}, true
			}
		}
	case .Palette:
		#partial switch button {
		case .Dpad_Up:
			return .Up, {}, true
		case .Dpad_Down:
			return .Down, {}, true
		case .Dpad_Left:
			return .Left, {}, true
		case .Dpad_Right:
			return .Right, {}, true
		case .South:
			return .Enter, {}, true
		case .East:
			return .Escape, {}, true
		case .Left_Shoulder, .Right_Shoulder:
			return .Tab, {}, true
		}
	case .Placement:
		#partial switch button {
		case .East:
			return .Escape, {}, true
		case .Left_Shoulder, .Right_Shoulder:
			return .Tab, {}, true
		}
	case .World:
		#partial switch button {
		case .South:
			return .Space, {}, true
		}
	}
	return .None, {}, false
}

@(private)
route_gamepad_stick :: proc(
	r: ^Resolver,
	out: ^Routed_Frame,
	stick: [2]f32,
	owner: Owner,
	keys: ^[platform.MAX_KEY_EVENTS]platform.Key_Event,
	key_count: ^int,
) {
	x := stick_direction(stick.x, r.stick_x_dir)
	y := stick_direction(stick.y, r.stick_y_dir)
	if math.abs(x) >= math.abs(y) {
		y = 0
	} else {
		x = 0
	}

	sink := stick_sink(owner)
	route_stick_axis(r, out, &r.stick_x, x, .Left, .Right, sink, keys, key_count)
	route_stick_axis(r, out, &r.stick_y, y, .Up, .Down, sink, keys, key_count)
	r.stick_x_dir = x
	r.stick_y_dir = y
}

@(private)
stick_sink :: proc(owner: Owner) -> Sink {
	switch owner {
	case .Menu, .Inspector:
		return .UI
	case .Palette:
		return .Game
	case .World, .Placement:
		return .None
	}
	return .None
}

@(private)
route_stick_axis :: proc(
	r: ^Resolver,
	out: ^Routed_Frame,
	held: ^Held_Key,
	direction: i8,
	negative: platform.Key,
	positive: platform.Key,
	sink: Sink,
	keys: ^[platform.MAX_KEY_EVENTS]platform.Key_Event,
	key_count: ^int,
) {
	key: platform.Key
	if direction < 0 {
		key = negative
	} else if direction > 0 {
		key = positive
	}
	if held.key == key && held.sink == sink {
		return
	}
	if held.key != .None && held.sink != .None {
		if release_key(r, held.sink, held.key) {
			route_event(out, held.sink, .Key_Up, held.key, {}, keys, key_count)
		}
		held^ = {}
	}
	if key != .None && sink != .None {
		held^ = {key = key, sink = sink}
		if press_key(r, sink, key) {
			route_event(out, sink, .Key_Down, key, {}, keys, key_count)
		}
	}
}

@(private)
stick_direction :: proc(value: f32, previous: i8) -> i8 {
	if value >= GAMEPAD_STICK_PRESS {
		return 1
	}
	if value <= -GAMEPAD_STICK_PRESS {
		return -1
	}
	if math.abs(value) <= GAMEPAD_STICK_RELEASE {
		return 0
	}
	return previous
}

@(private)
release_gamepad :: proc(
	r: ^Resolver,
	out: ^Routed_Frame,
	keys: ^[platform.MAX_KEY_EVENTS]platform.Key_Event,
	key_count: ^int,
) {
	for button in platform.Gamepad_Button {
		held := r.buttons[button]
		if held.key != .None && held.sink != .None && release_key(r, held.sink, held.key) {
			route_event(out, held.sink, .Key_Up, held.key, {}, keys, key_count)
		}
		r.buttons[button] = {}
	}
	release_stick(r, out, &r.stick_x, keys, key_count)
	release_stick(r, out, &r.stick_y, keys, key_count)
	r.stick_x_dir = 0
	r.stick_y_dir = 0
}

@(private)
release_stick :: proc(
	r: ^Resolver,
	out: ^Routed_Frame,
	held: ^Held_Key,
	keys: ^[platform.MAX_KEY_EVENTS]platform.Key_Event,
	key_count: ^int,
) {
	if held.key != .None && held.sink != .None && release_key(r, held.sink, held.key) {
		route_event(out, held.sink, .Key_Up, held.key, {}, keys, key_count)
	}
	held^ = {}
}
