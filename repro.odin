#+vet explicit-allocators
package main

import "core:fmt"
import "core:log"
import "core:time"

import "src:frame"
import "src:game"

// The key is a file writer, not a control channel. The file lands outside the
// view, so the result is a notice.
write_repro :: proc(
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	hud: ^game.HUD_State,
	view: frame.Options,
) -> bool {
	buffer: [frame.SNAPSHOT_PATH_BYTES]u8
	path := fmt.bprintf(
		buffer[:],
		"runs/repro/repro-%d.json",
		time.time_to_unix(time.now()),
	)
	absolute, write_error := frame.scene_write(sim, debug, view, nil, path)
	ok := write_error == ""
	if ok {
		log.infof("snapshot: %s", absolute)
		delete(absolute, context.allocator)
	} else {
		log.errorf("snapshot: %s", write_error)
		delete(write_error, context.allocator)
	}
	game.hud_notice_scene_snapshot(hud, path, ok)
	return ok
}
