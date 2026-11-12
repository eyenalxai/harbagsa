#+vet explicit-allocators
package main

import "core:log"

import "src:game"
import "src:platform"

// A free pointer cannot recapture on the next click, so a menu or palette click
// never leaks into the world.
@(private)
sync_cursor :: proc(
	window: ^platform.Window,
	focus: game.Focus,
	current_captured: bool,
) {
	desired := !focus.pointer_free
	platform.set_click_capture(window, desired)
	if desired == current_captured {
		return
	}
	if desired {
		_ = platform.set_cursor_capture(window, true)
		return
	}
	if !platform.set_cursor_capture(window, false) {
		log.warn("harbagsa: cursor release failed; using the keyboard path")
	}
}
