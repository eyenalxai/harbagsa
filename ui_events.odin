#+vet explicit-allocators
package main

import "src:platform"
import "src:renderer"

UI_EVENT_CAPACITY :: platform.MAX_UI_EVENTS

UI_Event_Buffer :: struct {
	items: [UI_EVENT_CAPACITY]renderer.UI_Event,
	count: int,
}

// build_ui_events turns one raw platform frame into the flat Rune event batch.
// The platform records the events in arrival order; this only converts their
// coordinates and filters the pointer events the game still owns. The buffer is
// reused every frame; the returned slice is valid until the next call.
build_ui_events :: proc(
	events: platform.Events,
	buffer: ^UI_Event_Buffer,
	pointer_ui: bool,
) -> []renderer.UI_Event {
	buffer.count = 0
	for index in 0 ..< events.ui_event_count {
		event := events.ui_events[index]
		switch event.kind {
		case .Pointer_Move:
			if pointer_ui {
				push_pointer(buffer, renderer.UI_EVENT_POINTER_MOVE, event.pointer)
			}
		case .Pointer_Down:
			if pointer_ui {
				push_pointer(buffer, renderer.UI_EVENT_POINTER_DOWN, event.pointer)
			}
		case .Pointer_Up:
			if pointer_ui {
				push_pointer(buffer, renderer.UI_EVENT_POINTER_UP, event.pointer)
			}
		case .Pointer_Leave:
			if pointer_ui {
				push_ui_event(buffer, {kind = renderer.UI_EVENT_POINTER_LEAVE})
			}
		case .Wheel:
			if pointer_ui {
				push_ui_event(buffer, {
					kind = renderer.UI_EVENT_WHEEL,
					x = event.pointer.x,
					y = event.pointer.y,
					dy = event.wheel,
				})
			}
		case .Key_Down, .Key_Up, .Key_Repeat:
			code := ui_key_code(event.key)
			if code == renderer.UI_KEY_NONE {
				continue
			}
			kind := renderer.UI_EVENT_KEY_DOWN
			if event.kind == .Key_Up {
				kind = renderer.UI_EVENT_KEY_UP
			} else if event.kind == .Key_Repeat {
				kind = renderer.UI_EVENT_KEY_REPEAT
			}
			push_ui_event(buffer, {kind = kind, key = code})
		case .Focus_Gained:
			push_ui_event(buffer, {kind = renderer.UI_EVENT_FOCUS, flags = 1})
		case .Focus_Lost:
			push_ui_event(buffer, {kind = renderer.UI_EVENT_FOCUS, flags = 0})
		}
	}
	return buffer.items[:buffer.count]
}

@(private)
push_pointer :: proc(buffer: ^UI_Event_Buffer, kind: u32, pointer: [2]f32) {
	push_ui_event(buffer, {kind = kind, x = pointer.x, y = pointer.y})
}

@(private)
push_ui_event :: proc(buffer: ^UI_Event_Buffer, event: renderer.UI_Event) {
	buffer.items[buffer.count] = event
	buffer.count += 1
}

@(private)
ui_key_code :: proc(key: platform.Key) -> i32 {
	#partial switch key {
	case .Up:
		return renderer.UI_KEY_UP
	case .Down:
		return renderer.UI_KEY_DOWN
	case .Left:
		return renderer.UI_KEY_LEFT
	case .Right:
		return renderer.UI_KEY_RIGHT
	case .Enter:
		return renderer.UI_KEY_ENTER
	case .Escape:
		return renderer.UI_KEY_ESCAPE
	case .Tab:
		return renderer.UI_KEY_TAB
	}
	return renderer.UI_KEY_NONE
}
