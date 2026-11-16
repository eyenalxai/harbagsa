#+vet explicit-allocators
#+vet !unused-procedures // the window loop calls this API; the game binary does not
package input

import "core:log"
import "core:math"

import "src:game"
import "src:platform"

GAMEPAD_LOOK_PER_FRAME :: f32(8.0)
GAMEPAD_STICK_PRESS :: f32(0.5)
GAMEPAD_STICK_RELEASE :: f32(0.4)

// route is the only pass that turns one raw platform frame into game intent and
// UI events. The owner comes from the pre-frame focus; each event then has one
// sink and is copied to exactly one of them.
route :: proc(
	r: ^Resolver,
	events: platform.Events,
	focus: game.Focus,
	captured: bool,
) -> Routed_Frame {
	out := Routed_Frame {
		owner        = owner_for(focus),
		pointer_free = focus.pointer_free,
		overflow     = events.overflow,
	}
	if focus.menu_open || !captured || focus.editor.active {
		clear_latches(r)
	}

	keys: [platform.MAX_KEY_EDGES]platform.Key_Edge
	key_count := 0
	pointer_ui := out.owner == .Menu || out.owner == .Inspector || out.owner == .Palette

	for index in 0 ..< events.raw_count {
		event := events.raw[index]
		switch event.kind {
		case .Key_Down, .Key_Repeat, .Key_Up:
			sink := route_key(r, out.owner, event)
			if sink == .UI {
				push_ui(&out, event)
			} else if event.kind == .Key_Down {
				append_key(&keys, &key_count, {key = event.key, mods = event.mods}, &out.overflow)
			}
		case .Pointer_Move, .Pointer_Down, .Pointer_Up, .Wheel:
			if pointer_ui {
				push_ui(&out, event)
			}
		case .Pointer_Leave, .Focus_Gained, .Focus_Lost:
			push_ui(&out, event)
		}
	}

	pad_primary, pad_menu := route_gamepad(r, &out, events.gamepad, &keys, &key_count)

	if out.owner == .Menu {
		return out
	}

	pad := events.gamepad
	game_events := events
	if pointer_ui {
		game_events.primary_pressed = false
		game_events.primary_released = false
		game_events.secondary_pressed = false
		game_events.wheel_delta = 0
	}
	game_events.move_forward = clamp(events.move_forward - pad.left.y, -1.0, 1.0)
	game_events.move_right = clamp(events.move_right + pad.left.x, -1.0, 1.0)
	game_events.look_delta.x += pad.right.x * GAMEPAD_LOOK_PER_FRAME
	game_events.look_delta.y += pad.right.y * GAMEPAD_LOOK_PER_FRAME
	game_events.primary_pressed = events.primary_pressed || pad_primary

	out.game = resolve(r, game_events, keys[:key_count], focus, captured)
	out.game.view.menu_toggle = out.game.view.menu_toggle || pad_menu
	out.overflow = out.overflow || out.game.overflow
	return out
}

@(private)
owner_for :: proc(focus: game.Focus) -> Owner {
	if focus.menu_open {
		return .Menu
	}
	if focus.inspector_open {
		return .Inspector
	}
	if focus.editor.active {
		if focus.editor.tool == .Palette {
			return .Palette
		}
		return .Placement
	}
	return .World
}

@(private)
key_sink_for :: proc(owner: Owner, key: platform.Key) -> Sink {
	switch owner {
	case .Menu:
		return .UI
	case .Inspector:
		// The inspector is a Rune surface, but its two engine toggles stay in the
		// engine so the focus path cannot close the wrong layer.
		if key == .Escape || key == .I {
			return .Game
		}
		return .UI
	case .World, .Palette, .Placement:
		return .Game
	}
	return .None
}

@(private)
route_key :: proc(r: ^Resolver, owner: Owner, event: platform.Input_Event) -> Sink {
	sink := r.key_sink[int(event.key)]
	#partial switch event.kind {
	case .Key_Down:
		sink = key_sink_for(owner, event.key)
		r.key_sink[int(event.key)] = sink
	case .Key_Repeat:
		if sink == .None {
			sink = key_sink_for(owner, event.key)
			r.key_sink[int(event.key)] = sink
		}
	case .Key_Up:
		r.key_sink[int(event.key)] = .None
		if sink == .None {
			sink = key_sink_for(owner, event.key)
		}
	case:
		return .None
	}
	return sink
}

@(private)
append_key :: proc(
	keys: ^[platform.MAX_KEY_EDGES]platform.Key_Edge,
	count: ^int,
	edge: platform.Key_Edge,
	overflow: ^bool,
) {
	if count^ >= len(keys) {
		overflow^ = true
		return
	}
	keys[count^] = edge
	count^ += 1
}

@(private)
push_ui :: proc(out: ^Routed_Frame, event: platform.Input_Event) {
	if out.ui_event_count >= len(out.ui_events) {
		out.overflow = true
		log.warn("input: the routed UI event buffer is full")
		return
	}
	out.ui_events[out.ui_event_count] = event
	out.ui_event_count += 1
}

@(private)
route_gamepad :: proc(
	r: ^Resolver,
	out: ^Routed_Frame,
	pad: platform.Gamepad_State,
	keys: ^[platform.MAX_KEY_EDGES]platform.Key_Edge,
	key_count: ^int,
) -> (
	primary_pressed: bool,
	menu_toggle: bool,
) {
	if !pad.connected {
		release_stick_key(out, r.stick_x, .Left, .Right)
		release_stick_key(out, r.stick_y, .Up, .Down)
		r.stick_x = 0
		r.stick_y = 0
		return
	}

	if out.owner == .Menu || out.owner == .Inspector {
		route_gamepad_stick(r, out, pad.left)
	} else {
		release_stick_key(out, r.stick_x, .Left, .Right)
		release_stick_key(out, r.stick_y, .Up, .Down)
		r.stick_x = 0
		r.stick_y = 0
	}

	for button in platform.Gamepad_Button {
		key, mods, mapped := gamepad_key(out.owner, button)
		if !mapped {
			continue
		}
		if button in pad.pressed {
			sink := key_sink_for(out.owner, key)
			r.key_sink[int(key)] = sink
			if sink == .UI {
				push_ui(out, {kind = .Key_Down, key = key, mods = mods})
			} else {
				append_key(keys, key_count, {key = key, mods = mods}, &out.overflow)
			}
		}
		if button in pad.released {
			sink := r.key_sink[int(key)]
			if sink == .None {
				sink = key_sink_for(out.owner, key)
			}
			if sink == .UI {
				push_ui(out, {kind = .Key_Up, key = key, mods = mods})
			}
			r.key_sink[int(key)] = .None
		}
	}

	if out.owner == .Placement && .South in pad.pressed {
		primary_pressed = true
	}
	if out.owner != .Menu && .Start in pad.pressed {
		menu_toggle = true
	}
	return
}

// gamepad_key maps the pad to the same key vocabulary the keyboard uses. The
// UI never sees a gamepad type; it receives a normalized key event at the ABI.
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
route_gamepad_stick :: proc(r: ^Resolver, out: ^Routed_Frame, stick: [2]f32) {
	x := stick_direction(stick.x, r.stick_x)
	y := stick_direction(stick.y, r.stick_y)
	if math.abs(x) >= math.abs(y) {
		y = 0
	} else {
		x = 0
	}
	if x != r.stick_x {
		release_stick_key(out, r.stick_x, .Left, .Right)
		r.stick_x = x
		if x < 0 {
			push_ui(out, {kind = .Key_Down, key = .Left})
		} else if x > 0 {
			push_ui(out, {kind = .Key_Down, key = .Right})
		}
	}
	if y != r.stick_y {
		release_stick_key(out, r.stick_y, .Up, .Down)
		r.stick_y = y
		if y < 0 {
			push_ui(out, {kind = .Key_Down, key = .Up})
		} else if y > 0 {
			push_ui(out, {kind = .Key_Down, key = .Down})
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
release_stick_key :: proc(
	out: ^Routed_Frame,
	previous: i8,
	negative: platform.Key,
	positive: platform.Key,
) {
	if previous < 0 {
		push_ui(out, {kind = .Key_Up, key = negative})
	} else if previous > 0 {
		push_ui(out, {kind = .Key_Up, key = positive})
	}
}
