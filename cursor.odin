#+vet explicit-allocators
package main

import "core:log"

import "src:game"
import "src:platform"

// Whether the palette hit test can read the pointer.
Cursor_State :: struct {
	pointer_available: bool,
}

// A free pointer cannot recapture on the next click, so a menu or palette click
// never leaks into the world.
@(private)
sync_cursor :: proc(
	window: ^platform.Window,
	focus: game.Focus,
	current_captured: bool,
	state: ^Cursor_State,
) {
	desired := !focus.pointer_free
	platform.set_click_capture(window, desired)
	if desired == current_captured {
		state.pointer_available = !desired
		return
	}
	if desired {
		state.pointer_available = false
		_ = platform.set_cursor_capture(window, true)
		return
	}
	released := !platform.set_cursor_capture(window, false)
	state.pointer_available = released
	if !released {
		log.warn("harbagsa: cursor release failed; using the keyboard path")
	}
}
