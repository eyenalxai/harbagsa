#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:log"
import "core:mem"
import "core:strings"

import "src:bake"
import "src:game"

Bake_Command :: struct {
	probe_spacing:     f32,
	has_probe_spacing: bool,
	threads:           int,
	has_threads:       bool,
	out:               string,
	has_out:           bool,
}

@(private)
parse_bake :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "probe_spacing", "threads", "out"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Bake}
	if value, has := json_get(object, "probe_spacing"); has {
		spacing, ok := json_number(value)
		if !ok ||
		   (spacing != f64(bake.PROBE_SPACING) &&
			   spacing != f64(bake.PROBE_SPACING_FALLBACK)) {
			return {}, format_error("%s", "'probe_spacing' must be 1 or 2")
		}
		command.bake.probe_spacing = f32(spacing)
		command.bake.has_probe_spacing = true
	}
	if value, has := json_get(object, "threads"); has {
		threads, ok := json_integer(value)
		if !ok || threads < 1 || threads > bake.MAX_THREADS {
			return {}, format_error("'threads' must be in [1, %d]", bake.MAX_THREADS)
		}
		command.bake.threads = threads
		command.bake.has_threads = true
	}
	if value, has := json_get(object, "out"); has {
		path, ok := json_string(value)
		if !ok || path == "" {
			return {}, format_error("%s", "'out' must be a non-empty string")
		}
		command.bake.out = strings.clone(path, allocator)
		command.bake.has_out = true
	}
	return command, ""
}

@(private)
destroy_bake_command :: proc(command: ^Command, allocator: mem.Allocator) {
	if command.bake.has_out {
		delete(command.bake.out, allocator)
	}
	command^ = {}
}

session_bake :: proc(session: ^Session, command: Bake_Command) -> string {
	if session.render.backend == nil ||
	   !session.render.backend.ready ||
	   session.render.backend.publish_bake == nil {
		return format_error("%s", "bake needs a renderer to publish")
	}

	quality := bake.DEFAULT_QUALITY
	if command.has_probe_spacing {
		quality.probe_spacing = command.probe_spacing
	}
	threads := command.threads
	if !command.has_threads {
		default_threads, counted := bake.default_threads()
		if !counted {
			log.warn("harness: cannot read the CPU count; baking with one thread")
		}
		threads = default_threads
	}

	static := game.simulation_bake_input(&session.sim, &session.scratch.bake, session.allocator)
	artifact, report, build_error := bake.build(
		static,
		{quality = quality, threads = threads},
		session.allocator,
	)
	if build_error != .None {
		return format_error("bake: %s", bake.build_error_name(build_error))
	}

	if command.has_out {
		if write_error := bake.write_file(command.out, artifact); write_error != "" {
			delete(artifact, session.allocator)
			return write_error
		}
	}

	published, publish_error := session.render.backend.publish_bake(
		session.render.backend.ctx,
		artifact,
		report.bake_ms,
	)
	if !published {
		return publish_error
	}
	log.infof(
		"harness: bake key %016x boxes %d lights %d probes %d in %d ms",
		report.key,
		report.boxes,
		report.lights,
		report.probes,
		report.bake_ms,
	)
	return ""
}
