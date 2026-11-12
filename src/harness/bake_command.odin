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
	probe_basis:       bake.Probe_Basis,
	has_probe_basis:   bool,
	probe_moments:     u32,
	has_probe_moments: bool,
	scale:             f32,
	has_scale:         bool,
	threads:           int,
	has_threads:       bool,
	out:               string,
	has_out:           bool,
}

@(private)
parse_bake :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(
		object,
		{"cmd", "probe_spacing", "probe_basis", "probe_moments", "scale", "threads", "out"},
	); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Bake}
	if value, has := json_get(object, "probe_basis"); has {
		name, ok := json_string(value)
		basis, parsed := bake.probe_basis_parse(name)
		if !ok || !parsed {
			return {}, format_error("%s", "'probe_basis' must be octa or sh9")
		}
		command.bake.probe_basis = basis
		command.bake.has_probe_basis = true
	}
	if value, has := json_get(object, "probe_moments"); has {
		moments, ok := json_integer(value)
		if !ok || !bake.probe_moments_supported(u32(moments)) {
			return {}, format_error("%s", "'probe_moments' must be 8 or 16")
		}
		command.bake.probe_moments = u32(moments)
		command.bake.has_probe_moments = true
	}
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
	if value, has := json_get(object, "scale"); has {
		scale, ok := json_number(value)
		if !ok || !bake.scale_supported(f32(scale)) {
			return {}, format_error("%s", "'scale' must be in (0, 8]")
		}
		command.bake.scale = f32(scale)
		command.bake.has_scale = true
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
	if command.has_probe_basis {
		quality.probe_basis = u32(command.probe_basis)
	}
	if command.has_probe_moments {
		quality.probe_moment_texels = command.probe_moments
	}
	threads := command.threads
	if !command.has_threads {
		default_threads, counted := bake.default_threads()
		if !counted {
			log.warn("harness: cannot read the CPU count; baking with one thread")
		}
		threads = default_threads
	}

	static := game.simulation_bake_input(
		&session.runtime.sim,
		&session.runtime.scratch.bake,
		session.allocator,
	)
	if command.has_scale {
		bake.scale_static(static, command.scale)
	}
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
		if time_error := bake.write_time(command.out, report.bake_ms); time_error != "" {
			log.warnf("harness: %s", time_error)
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
		"harness: bake key %016x boxes %d lights %d probes %d basis %s moments %d allocated %d occupancy %.2f%% in %d ms",
		report.key,
		report.boxes,
		report.lights,
		report.probes,
		bake.probe_basis_name(report.probe_basis),
		report.probe_moments,
		report.allocated_texels,
		f64(report.occupancy) * 100.0,
		report.bake_ms,
	)
	return ""
}
