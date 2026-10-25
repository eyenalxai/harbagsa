#+vet explicit-allocators
package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:time"

import "src:frame"
import "src:game"

// The key is a file writer, not a control channel. The agent still owns the
// scenario runner; this only freezes the live view into one runnable file.
write_repro :: proc(
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	hud: ^game.HUD_State,
	view: frame.Options,
) -> bool {
	scene := frame.scene_capture(
		sim,
		debug,
		hud,
		view,
		nil,
		context.temp_allocator,
	)
	defer frame.scene_destroy(&scene, context.temp_allocator)
	text := frame.scene_json(scene, context.temp_allocator)
	if text == "" {
		log.error("repro: cannot encode the scene")
		return false
	}
	if make_error := os.make_directory_all("runs/repro"); make_error != nil && make_error != .Exist {
		log.errorf("repro: cannot create runs/repro: %v", make_error)
		return false
	}
	path := fmt.aprintf(
		"runs/repro/repro-%d.json",
		time.time_to_unix(time.now()),
		allocator = context.temp_allocator,
	)
	if write_error := os.write_entire_file(path, text); write_error != nil {
		log.errorf("repro: cannot write %s: %v", path, write_error)
		return false
	}
	absolute := path
	if working_directory, working_error := os.get_working_directory(context.temp_allocator); working_error == nil {
		absolute = fmt.aprintf(
			"%s/%s",
			working_directory,
			path,
			allocator = context.temp_allocator,
		)
	}
	log.infof("repro: %s", absolute)
	return true
}
