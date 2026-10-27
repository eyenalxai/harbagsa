#+vet explicit-allocators
package game

import b3 "libs:box3d"

debug_mode_update :: proc(
	dm: ^Debug_Mode,
	sim: ^Simulation,
	motion: Debug_Motion,
	actions: []Edit_Action,
	menu_open: bool,
	delta: f32,
) {
	if !dm.active {
		return
	}
	if !motion.captured {
		debug_mode_end_drag(dm)
	}

	primary_press := edit_actions_have_primary_press(actions)
	if motion.captured && dm.dragging == .None && !primary_press {
		dm.camera.yaw = b3.UnwindAngle(dm.camera.yaw - motion.look_delta.x * YAW_SENSITIVITY)
		dm.camera.pitch = clamp(
			dm.camera.pitch - motion.look_delta.y * PITCH_SENSITIVITY,
			CAMERA_PITCH_MIN,
			CAMERA_PITCH_MAX,
		)
	}

	debug_fly(dm, motion, delta)
	// The aim belongs to the camera, so refresh the tool before an action reads
	// the ghost.
	if dm.placement.armed {
		debug_placement_refresh(dm, sim)
	}
	if _, ok := debug_selected_object_id(dm, sim); !ok && dm.selection == .Object {
		debug_mode_clear_selection(dm)
	}
	ctx := Edit_Context{menu_open = menu_open, captured = motion.captured}
	for action in actions {
		_ = edit_apply(dm, sim, action, ctx)
	}
	if dm.placement.armed {
		debug_placement_refresh(dm, sim)
	}
}

@(private)
edit_actions_have_primary_press :: proc(actions: []Edit_Action) -> bool {
	for action in actions {
		#partial switch action in action {
		case Primary_Press:
			return true
		}
	}
	return false
}


@(private)
debug_fly :: proc(dm: ^Debug_Mode, motion: Debug_Motion, delta: f32) {
	if delta <= 0.0 {
		return
	}

	forward := debug_camera_forward_horizontal(dm.camera)
	right := debug_camera_right(dm.camera)
	move := forward * motion.move_forward + right * motion.move_right
	move.y = motion.move_up
	length := b3.Length(move)
	if length > 1.0 {
		move = move * (1.0 / length)
	}
	dm.camera.position += move * (DEBUG_FLY_SPEED * delta)
}
