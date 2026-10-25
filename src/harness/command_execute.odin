#+vet explicit-allocators
package harness

import "core:math"

import b3 "libs:box3d"

import "src:frame"
import "src:game"

@(private)
execute_reset :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_reset(session)
}

@(private)
execute_look :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	game.simulation_look(&session.sim, b3.Vec2{command.look.dx, command.look.dy})
	return ""
}

@(private)
execute_face :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	game.simulation_face(&session.sim, command.face.yaw_rad, command.face.pitch_rad)
	return ""
}

@(private)
execute_input :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	session_apply_input(session, command.input)
	return ""
}

@(private)
execute_step :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_step(session, command.step.frames)
}

@(private)
execute_settle :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_settle(session, command.settle)
}

@(private)
execute_state :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	reply.state = new(State, session.allocator)
	reply.state^ = session_state(session)
	return ""
}

@(private)
execute_capture :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	immediate, capture_error := session_queue_capture(session, command.capture)
	if capture_error == "" && immediate && len(session.captures) > 0 {
		reply.capture = &session.captures[len(session.captures) - 1]
	}
	return capture_error
}

@(private)
execute_captures :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	immediate, capture_error := session_queue_captures(session, command.captures)
	if capture_error == "" && immediate && len(session.captures) > 0 {
		reply.capture = &session.captures[len(session.captures) - 1]
	}
	return capture_error
}

@(private)
execute_camera :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if command.camera.clear {
		session.camera_override = {}
		session.has_camera_override = false
		return ""
	}
	fov := frame.PLAYER_FOV_X
	if command.camera.has_fov {
		fov = math.to_radians(command.camera.fov_deg)
	}
	session.camera_override = {
		position = command.camera.position,
		yaw      = command.camera.yaw_rad,
		pitch    = command.camera.pitch_rad,
		fov_x    = fov,
	}
	session.has_camera_override = true
	return ""
}

@(private)
execute_view :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if command.view.has_hud {
		session.view.hud = command.view.hud
	}
	if command.view.has_debug {
		session.view.debug = command.view.debug
	}
	if command.view.has_hint {
		session.view.hint = command.view.hint
	}
	if command.view.has_perf {
		session.view.perf = command.view.perf
	}
	return ""
}

@(private)
execute_sun :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	session_sun(session, command.sun)
	return ""
}

@(private)
execute_scene :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_scene(session, command.scene)
}

@(private)
execute_place :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_place(session, command.place, reply)
}

@(private)
execute_remove :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_remove(session, command.remove)
}

@(private)
execute_get :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_get(session, command.get, reply)
}

@(private)
execute_debug_mode :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if session.debug.active != command.debug_mode.active {
		game.debug_mode_toggle(&session.debug, &session.sim)
	}
	return ""
}

@(private)
execute_editor :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_editor(session, command.editor)
}

@(private)
execute_menu :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_menu(session, command.menu)
}

@(private)
execute_check :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_check_command(session, command.check, reply)
}

@(private)
execute_record :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if command.record.has_path {
		return session_record_start(session, command.record.path, !command.record.actions)
	}
	recorded, record_error := session_record_stop(session)
	if record_error != "" {
		return record_error
	}
	reply.recorded = recorded
	return ""
}

@(private)
execute_replay :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	summary, replay_error := session_replay(session, command.replay.path)
	if replay_error != "" {
		return replay_error
	}
	reply.replay = new(Replay_Summary, session.allocator)
	reply.replay^ = summary
	return ""
}

@(private)
execute_repro :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_repro(session, command.repro.path, reply)
}

@(private)
execute_perf :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	perf_error := session_perf(session, command.perf)
	if perf_error == "" {
		reply.perf = &session.perf_report
	}
	return perf_error
}

@(private)
execute_renderer_debug :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	return session_renderer_debug(session, command.renderer_debug)
}

@(private)
execute_displays :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	session_displays(session, command.displays)
	reply.displays = new(Displays_State, session.allocator)
	reply.displays^ = displays_state_build(&session.sim.settings.display, session.allocator)
	return ""
}

@(private)
execute_rows :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	session_refresh_hud(session)
	reply.rows = new(Rows_State, session.allocator)
	reply.rows^ = rows_state_build(&session.hud, session.allocator)
	return ""
}

@(private)
execute_quit :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if session.recording {
		recorded, record_error := session_record_stop(session)
		if recorded != "" {
			delete(recorded, session.allocator)
		}
		if record_error != "" {
			delete(record_error, context.allocator)
		}
	}
	session.quit = true
	return ""
}
