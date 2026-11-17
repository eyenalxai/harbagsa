#+vet explicit-allocators
package main

import "core:log"

import "src:appframe"
import "src:display"
import "src:frame"
import "src:game"
import "src:platform"
import "src:renderer"

// Loop is the mutable state of the window loop. main owns the lifetime; the
// loop module owns the phases, and the frame path itself lives in appframe.
Loop :: struct {
	app:       appframe.State,
	window:    ^platform.Window,
	displays:  platform.Displays,
	repro_dir: string,
}

loop_hooks :: proc(loop: ^Loop) -> appframe.Hooks {
	return {
		user = loop,
		apply_window = apply_window_hook,
		sync_cursor = sync_cursor_hook,
		write_repro = write_repro_hook,
	}
}

@(private)
apply_window_hook :: proc(user: rawptr, previous: display.Window_Settings) {
	loop := cast(^Loop)user
	result := platform.apply_window_state(
		loop.window,
		&loop.displays,
		loop.app.runtime.sim.settings.window,
	)
	if result == .Applied {
		renderer.notify_resize(loop.app.renderer)
		return
	}
	loop.app.runtime.sim.settings.window = previous
	restore := platform.apply_window_state(loop.window, &loop.displays, previous)
	restored := restore == .Applied
	if restored {
		renderer.notify_resize(loop.app.renderer)
	} else {
		log.warnf(
			"harbagsa: the previous window settings were not restored: %s",
			platform.window_apply_name(restore),
		)
	}
	game.menu_window_apply_failed(
		&loop.app.runtime.hud.menu,
		platform.window_apply_name(result),
		restored,
	)
}

@(private)
sync_cursor_hook :: proc(user: rawptr, pointer_free: bool, captured: bool) {
	loop := cast(^Loop)user
	sync_cursor(loop.window, pointer_free, captured)
}

@(private)
write_repro_hook :: proc(app: ^appframe.State, user: rawptr) {
	loop := cast(^Loop)user
	debug := renderer.renderer_debug(loop.app.renderer)
	_ = write_repro(
		&app.runtime.sim,
		&app.runtime.debug,
		&app.runtime.hud,
		frame.Options {
			alpha = app.last_alpha,
			debug_view = app.runtime.debug.physics_debug,
			captured = app.captured,
			hud = true,
		},
		&debug,
		loop.repro_dir,
	)
}
