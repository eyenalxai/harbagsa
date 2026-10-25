#+vet explicit-allocators
package main

import "core:log"

import "src:platform"

Cursor_State :: struct {
	palette_was_open:  bool,
	pointer_available: bool,
}

// sync_palette_cursor frees the cursor while the object palette is open and
// captures it when the palette closes. The settings menu owns the cursor
// separately, so the palette leaves it alone while the menu is open.
@(private)
sync_palette_cursor :: proc(
	window: ^platform.Window,
	debug_active: bool,
	menu_open: bool,
	want_free: bool,
	state: ^Cursor_State,
) {
	if !debug_active || menu_open {
		// The palette cannot be open outside debug mode, and opening the menu
		// cancels editing. The old sync stored the post-cancel palette flag.
		state.palette_was_open = false
		return
	}
	if want_free == state.palette_was_open {
		return
	}
	state.palette_was_open = want_free
	if want_free {
		platform.set_click_capture(window, false)
		released := !platform.set_cursor_capture(window, false)
		state.pointer_available = released
		if !released {
			log.warn("harbagsa: cursor release for the palette failed; using the keyboard path")
		}
		return
	}
	platform.set_click_capture(window, true)
	_ = platform.set_cursor_capture(window, true)
	state.pointer_available = false
}
