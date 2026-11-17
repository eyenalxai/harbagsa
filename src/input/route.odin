#+vet explicit-allocators
#+vet !unused-procedures // the window loop calls this API; the game binary does not
package input

import "core:log"

import "src:game"
import "src:platform"

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
		owner    = owner_for(focus),
		overflow = events.overflow,
	}
	primary_release := false
	keys: [platform.MAX_KEY_EVENTS]platform.Key_Event
	key_count := 0
	if events.overflow {
		primary_release = r.pad_primary
		release_all_held(r, &out, &keys, &key_count)
	}

	pointer_ui := pointer_is_ui(out.owner)

	for index in 0 ..< events.raw_count {
		event := events.raw[index]
		switch event.kind {
		case .Key_Down, .Key_Repeat, .Key_Up:
			route_keyboard(r, &out, out.owner, event, &keys, &key_count)
		case .Pointer_Move, .Pointer_Down, .Pointer_Up, .Wheel:
			if pointer_ui {
				push_ui(&out, event)
			}
		case .Pointer_Leave, .Focus_Gained:
			push_ui(&out, event)
		case .Focus_Lost:
			primary_release = primary_release || r.pad_primary
			clear_held(r)
			clear_latches(r)
			push_ui(&out, event)
		}
	}

	pad_primary, pad_release, pad_menu := route_gamepad(r, &out, events.gamepad, &keys, &key_count)

	pad := events.gamepad
	game_events := events
	if pointer_ui {
		game_events.primary_pressed = false
		game_events.primary_released = false
		game_events.secondary_pressed = false
		game_events.wheel_delta = 0
	}
	if !pointer_is_ui(out.owner) {
		game_events.move_forward = clamp(events.move_forward - pad.left.y, -1.0, 1.0)
		game_events.move_right = clamp(events.move_right + pad.left.x, -1.0, 1.0)
	}
	game_events.look_delta.x += pad.right.x * GAMEPAD_LOOK_PER_FRAME
	game_events.look_delta.y += pad.right.y * GAMEPAD_LOOK_PER_FRAME
	game_events.primary_pressed = game_events.primary_pressed || pad_primary
	game_events.primary_released = game_events.primary_released || pad_release || primary_release

	out.game = resolve(r, game_events, keys[:key_count], focus, out.owner, captured)
	out.game.view.menu_toggle = out.game.view.menu_toggle || pad_menu
	out.overflow = out.overflow || out.game.overflow
	report_overflow(&out, events.overflow)
	return out
}

@(private)
report_overflow :: proc(out: ^Routed_Frame, raw_overflow: bool) {
	if out.overflow && !raw_overflow {
		log.warn("input: the route dropped an input event; a key or UI queue is full")
	}
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
pointer_is_ui :: proc(owner: Owner) -> bool {
	return owner == .Menu || owner == .Inspector || owner == .Palette
}

@(private)
key_sink_for :: proc(owner: Owner, key: platform.Key) -> Sink {
	switch owner {
	case .Menu:
		return .UI
	case .Inspector:
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
route_keyboard :: proc(
	r: ^Resolver,
	out: ^Routed_Frame,
	owner: Owner,
	event: platform.Input_Event,
	keys: ^[platform.MAX_KEY_EVENTS]platform.Key_Event,
	key_count: ^int,
) {
	if event.kind == .Key_Down {
		sink := key_sink_for(owner, event.key)
		r.keyboard[int(event.key)] = sink
		if press_key(r, sink, event.key) {
			route_event(out, sink, .Key_Down, event.key, event.mods, keys, key_count)
		}
		return
	}

	sink := r.keyboard[int(event.key)]
	if event.kind == .Key_Up {
		r.keyboard[int(event.key)] = .None
		if release_key(r, sink, event.key) {
			route_event(out, sink, .Key_Up, event.key, event.mods, keys, key_count)
		}
		return
	}
	if sink != .None {
		route_event(out, sink, event.kind, event.key, event.mods, keys, key_count)
	}
}

@(private)
route_event :: proc(
	out: ^Routed_Frame,
	sink: Sink,
	kind: platform.Input_Kind,
	key: platform.Key,
	mods: platform.Modifiers,
	keys: ^[platform.MAX_KEY_EVENTS]platform.Key_Event,
	key_count: ^int,
) {
	switch sink {
	case .UI:
		push_ui(out, {kind = kind, key = key, mods = mods})
	case .Game:
		append_key(keys, key_count, {kind = kind, key = key, mods = mods}, &out.overflow)
	case .None:
	}
}

@(private)
append_key :: proc(
	keys: ^[platform.MAX_KEY_EVENTS]platform.Key_Event,
	count: ^int,
	event: platform.Key_Event,
	overflow: ^bool,
) {
	if count^ >= len(keys) {
		overflow^ = true
		return
	}
	keys[count^] = event
	count^ += 1
}

@(private)
push_ui :: proc(out: ^Routed_Frame, event: platform.Input_Event) {
	if out.ui_event_count >= len(out.ui_events) {
		out.overflow = true
		return
	}
	out.ui_events[out.ui_event_count] = event
	out.ui_event_count += 1
}
