#+vet explicit-allocators
package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:time"

import "src:frame"
import "src:game"
import "src:renderer"

repro_directory :: proc(args: []string) -> (string, bool) {
	directory := os.get_env("HARBAGSA_REPRO_DIR", context.temp_allocator)
	if directory == "" {
		directory = frame.REPRO_DEFAULT_DIR
	}
	for index := 0; index < len(args); index += 1 {
		argument := args[index]
		switch {
		case argument == "--repro-dir":
			if index + 1 >= len(args) {
				log.error("harbagsa: --repro-dir needs a directory")
				return "", false
			}
			directory = args[index + 1]
			index += 1
		case strings.has_prefix(argument, "--repro-dir="):
			directory = argument[len("--repro-dir="):]
		}
	}
	return directory, true
}

// The key is a file writer, not a control channel. The file lands outside the
// view, so the result is a notice.
write_repro :: proc(
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	hud: ^game.HUD_State,
	view: frame.Options,
	renderer_debug: ^renderer.Renderer_Debug,
	directory: string,
) -> bool {
	buffer: [frame.SNAPSHOT_PATH_BYTES]u8
	milliseconds := time.time_to_unix_nano(time.now()) / 1_000_000
	path := fmt.bprintf(
		buffer[:],
		"%s/repro-%d.json",
		directory,
		milliseconds,
	)
	absolute, write_error := frame.scene_write(
		sim,
		debug,
		view,
		nil,
		renderer_debug,
		path,
	)
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
