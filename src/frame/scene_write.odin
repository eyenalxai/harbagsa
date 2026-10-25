#+vet explicit-allocators
#+vet !unused-procedures // the F5 key and the harness both write a scene snapshot
package frame

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "src:game"
import "src:renderer"

// The notice names the file, so the path must fit one notice line. The default
// `runs/repro/repro-<unix>.json` is half of this.
SNAPSHOT_PATH_BYTES :: 64

// A live view writes one runnable scenario. The key and the harness share this
// writer, so a repro from either side has one schema and one file shape.
//
// Both returned strings belong to the caller. The absolute path is empty on
// failure, and the error is empty on success.
scene_write :: proc(
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	hud: ^game.HUD_State,
	view: Options,
	camera_override: ^renderer.Camera,
	path: string,
) -> (absolute: string, error: string) {
	if path == "" || len(path) > SNAPSHOT_PATH_BYTES {
		return "", fmt.aprintf(
			"the path must hold 1..%d bytes",
			SNAPSHOT_PATH_BYTES,
			allocator = context.allocator,
		)
	}
	scene := scene_capture(sim, debug, hud, view, camera_override, context.temp_allocator)
	defer scene_destroy(&scene, context.temp_allocator)
	text := scene_json(scene, context.temp_allocator)
	if text == "" {
		return "", fmt.aprintf("cannot encode the scene", allocator = context.allocator)
	}
	directory := filepath.dir(path)
	if directory != "" && directory != "." {
		make_error := os.make_directory_all(directory)
		if make_error != nil && make_error != .Exist {
			return "", fmt.aprintf(
				"cannot create %s: %v",
				directory,
				make_error,
				allocator = context.allocator,
			)
		}
	}
	if write_error := os.write_entire_file(path, text); write_error != nil {
		return "", fmt.aprintf(
			"cannot write %s: %v",
			path,
			write_error,
			allocator = context.allocator,
		)
	}
	if working_directory, working_error := os.get_working_directory(context.temp_allocator); working_error == nil {
		return fmt.aprintf(
			"%s/%s",
			working_directory,
			path,
			allocator = context.allocator,
		), ""
	}
	return strings.clone(path, context.allocator), ""
}
