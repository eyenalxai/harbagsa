#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:sys/info"

import "src:bake"
import "src:game"

Bake_Action :: enum {
	Status,
	Reload,
	Publish,
}

Bake_Command :: struct {
	action:        Bake_Action,
	probe_spacing: f32,
	threads:       int,
}

BAKE_KEYS := [?]string{"cmd", "action", "probe_spacing", "threads"}

@(private)
parse_bake :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, BAKE_KEYS[:]); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command {
		kind = .Bake,
		bake = {
			action        = .Status,
			probe_spacing = f32(bake.PROBE_SPACING),
			threads       = harness_default_threads(),
		},
	}
	if value, has := json_get(object, "action"); has {
		name, name_ok := json_string(value)
		action, action_ok := bake_action_parse(name)
		if !name_ok || !action_ok {
			return {}, format_error("%s", "'action' must be status, reload, or publish")
		}
		command.bake.action = action
	}
	if value, has := json_get(object, "probe_spacing"); has {
		spacing, spacing_ok := json_number(value)
		if !spacing_ok ||
		   (spacing != f64(bake.PROBE_SPACING) && spacing != f64(bake.PROBE_SPACING_FALLBACK)) {
			return {}, format_error("%s", "'probe_spacing' must be 1 or 2")
		}
		command.bake.probe_spacing = f32(spacing)
	}
	if value, has := json_get(object, "threads"); has {
		threads, threads_ok := json_integer(value)
		if !threads_ok || threads < 1 || threads > bake.MAX_THREADS {
			return {}, format_error("'threads' must be between 1 and %d", bake.MAX_THREADS)
		}
		command.bake.threads = threads
	}
	return command, ""
}

@(private)
harness_default_threads :: proc() -> int {
	_, logical, ok := info.cpu_core_count()
	if !ok || logical < 1 {
		return 1
	}
	return clamp(logical, 1, bake.MAX_THREADS)
}

@(private)
bake_action_parse :: proc(name: string) -> (Bake_Action, bool) {
	switch name {
	case "status":
		return .Status, true
	case "reload":
		return .Reload, true
	case "publish":
		return .Publish, true
	}
	return .Status, false
}

@(private)
execute_bake :: proc(session: ^Session, command: Command, _reply: ^Reply) -> string {
	backend := session.render.backend
	if backend == nil || !backend.ready {
		return format_error("%s", "bake needs the renderer")
	}
	switch command.bake.action {
	case .Status:
		return ""
	case .Reload:
		if !backend.reload_bake(backend.ctx) {
			return format_error("%s", "bake reload failed; see state.bake.error")
		}
	case .Publish:
		static := game.simulation_bake_input(
			&session.sim,
			&session.scratch.bake,
			session.allocator,
		)
		quality := bake.DEFAULT_QUALITY
		quality.probe_spacing = command.bake.probe_spacing
		artifact, build_report, build_error := bake.build(
			static,
			{quality = quality, threads = command.bake.threads},
			session.allocator,
		)
		if build_error != .None {
			return format_error("bake: %s", bake.build_error_name(build_error))
		}
		if !backend.publish_bake(
			backend.ctx,
			artifact,
			build_report.bake_ms,
			command.bake.threads,
		) {
			return format_error("%s", "bake publish failed; see state.bake.error")
		}
	}
	return ""
}
