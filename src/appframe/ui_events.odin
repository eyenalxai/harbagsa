#+vet explicit-allocators
package appframe

import "src:platform"
import "src:renderer"

UI_EVENT_CAPACITY :: platform.MAX_INPUT_EVENTS

UI_Event_Buffer :: struct {
	items: [UI_EVENT_CAPACITY]renderer.UI_Event,
	count: int,
}

// build_ui_events converts the routed UI batch to the flat Rune event batch.
// The route has already chosen the sink, so this only maps coordinates, key
// codes, and modifiers; it never filters by another owner. The buffer is reused
// every frame; the returned slice is valid until the next call.
build_ui_events :: proc(
	events: []platform.Input_Event,
	buffer: ^UI_Event_Buffer,
) -> []renderer.UI_Event {
	buffer.count = 0
	for event in events {
		switch event.kind {
		case .Pointer_Move:
			push_pointer(buffer, renderer.UI_EVENT_POINTER_MOVE, event.pointer)
		case .Pointer_Down:
			push_pointer(buffer, renderer.UI_EVENT_POINTER_DOWN, event.pointer)
		case .Pointer_Up:
			push_pointer(buffer, renderer.UI_EVENT_POINTER_UP, event.pointer)
		case .Pointer_Leave:
			push_ui_event(buffer, {kind = renderer.UI_EVENT_POINTER_LEAVE})
		case .Wheel:
			push_ui_event(buffer, {
				kind = renderer.UI_EVENT_WHEEL,
				x = event.pointer.x,
				y = event.pointer.y,
				dy = event.wheel,
			})
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
			push_ui_event(buffer, {kind = kind, key = code, mods = ui_mods(event.mods)})
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
ui_mods :: proc(mods: platform.Modifiers) -> u32 {
	flags: u32
	if .Shift in mods {
		flags |= renderer.UI_MOD_SHIFT
	}
	if .Ctrl in mods {
		flags |= renderer.UI_MOD_CTRL
	}
	return flags
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
	case .Space:
		return renderer.UI_KEY_SPACE
	}
	return renderer.UI_KEY_NONE
}
