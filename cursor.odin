#+vet explicit-allocators
package main

import "core:log"

import "src:game"
import "src:platform"

// The capture state the loop has applied, and whether the palette hit test can
// read the pointer. The owner is derived from the current frame, not a latch.
Cursor_State :: struct {
	captured:          bool,
	pointer_available: bool,
}

// sync_cursor applies the one owner rule: the menu and the editor focus decide
// the relative mode and the click policy together. A free pointer cannot
// recapture on the next click, so a menu or palette click never leaks into the
// world.
@(private)
sync_cursor :: proc(window: ^platform.Window, focus: game.Focus, state: ^Cursor_State) {
	captured := !focus.menu_open && !focus.editor.pointer_free
	if captured == state.captured {
		return
	}
	platform.set_click_capture(window, captured)
	if captured {
		state.captured = platform.set_cursor_capture(window, true)
		state.pointer_available = !state.captured
		return
	}
	released := !platform.set_cursor_capture(window, false)
	state.captured = !released
	state.pointer_available = released
	if !released {
		log.warn("harbagsa: cursor release failed; using the keyboard path")
	}
}
