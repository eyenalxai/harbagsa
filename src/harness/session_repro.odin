#+vet explicit-allocators
package harness

import "core:path/filepath"
import "core:strings"

import "src:frame"
import "src:game"
import "src:renderer"

// The key and the harness write the same file. The command sets the notice too,
// so a scenario sees what the player sees.
session_repro :: proc(session: ^Session, path: string, reply: ^Reply) -> string {
	if path == "" {
		return format_error("%s", "repro needs a path")
	}
	target := path
	owned_target := false
	if session.output_dir != "" && !filepath.is_abs(path) {
		target = join_path({session.output_dir, path}, session.allocator)
		owned_target = true
	}
	defer if owned_target {
		delete(target, session.allocator)
	}
	if len(target) > frame.SNAPSHOT_PATH_BYTES {
		return format_error(
			"repro path must hold at most %d bytes",
			frame.SNAPSHOT_PATH_BYTES,
		)
	}
	options := frame.Options {
		hud        = session.view.hud,
		debug_view = session.view.debug,
		captured   = !session.view.hint,
		perf       = session.view.perf,
	}
	if session.has_probe_volumes {
		options.scene_probe_volumes = session.scene_probe_volumes
	}
	camera: ^renderer.Camera
	if session.has_camera_override {
		camera = &session.camera_override
	}
	debug: ^renderer.Renderer_Debug
	if session.render.debug.active {
		debug = &session.render.debug
	}
	absolute, write_error := frame.scene_write(
		&session.sim,
		&session.debug,
		options,
		camera,
		debug,
		target,
	)
	game.hud_notice_scene_snapshot(&session.hud, path, write_error == "")
	if write_error != "" {
		return write_error
	}
	reply.written = strings.clone(absolute, session.allocator)
	delete(absolute, context.allocator)
	return ""
}
