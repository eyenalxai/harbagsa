#+vet explicit-allocators
package harness

import "core:math"

import "src:game"

session_editor :: proc(session: ^Session, command: Editor_Command) -> string {
	if !session.debug.active {
		return format_error("%s", "editor needs debug mode; send {\"cmd\": \"debug_mode\", \"active\": true} first")
	}

	if command.has_camera {
		session.debug.camera = {
			position = command.camera.position,
			yaw      = command.camera.yaw_rad,
			pitch    = command.camera.pitch_rad,
		}
	}

	if command.has_open {
		action: game.Edit_Action = game.Palette_Close{}
		if command.open {
			action = game.Palette_Open{}
		}
		if failure := apply_editor_action(session, action); failure != "" {
			return failure
		}
	}
	if command.has_select {
		if failure := apply_editor_action(
			session,
			game.Palette_Select{index = command.select},
		); failure != "" {
			return failure
		}
	}
	if command.input.has_palette_step {
		if failure := apply_editor_action(
			session,
			game.Palette_Step{delta = command.input.palette_step},
		); failure != "" {
			return failure
		}
	}
	if command.input.has_palette_number {
		if failure := apply_editor_action(
			session,
			game.Palette_Select{index = command.input.palette_number - 1},
		); failure != "" {
			return failure
		}
	}
	if command.object.has_select_name {
		select_name := command.object.select_name
		name := object_name_text(&select_name)
		object, found := game.simulation_object_find_by_name(&session.sim, name)
		if !found {
			return format_error("object name %q does not exist", name)
		}
		if failure := apply_editor_action(
			session,
			game.Select_Object{id = object.id},
		); failure != "" {
			return failure
		}
	}
	if command.object.has_select_object {
		if failure := apply_editor_action(
			session,
			game.Select_Object{id = game.Object_Id(command.object.select_object)},
		); failure != "" {
			return failure
		}
	}
	if command.has_body {
		if failure := apply_editor_action(session, game.Set_Body{mode = command.body}); failure != "" {
			return failure
		}
	}
	if command.input.flip_body {
		if failure := apply_editor_action(session, game.Flip_Body{}); failure != "" {
			return failure
		}
	}
	if command.has_height {
		if failure := apply_editor_action(
			session,
			game.Placement_Set_Height{height = command.height},
		); failure != "" {
			return failure
		}
	}
	if command.has_yaw {
		if failure := apply_editor_action(session, game.Placement_Set_Yaw{yaw_deg = command.yaw_deg}); failure != "" {
			return failure
		}
	}
	if command.has_snap {
		if failure := apply_editor_action(session, game.Placement_Set_Snap{snap = command.snap}); failure != "" {
			return failure
		}
	}
	if command.input.snap_toggle {
		if failure := apply_editor_action(session, game.Placement_Toggle_Snap{}); failure != "" {
			return failure
		}
	}
	if command.light.has_kind {
		if failure := apply_editor_action(
			session,
			game.Light_Set_Kind{kind = command.light.kind},
		); failure != "" {
			return failure
		}
	}
	if command.light.has_color {
		if failure := apply_editor_action(
			session,
			game.Light_Set_Color{color = command.light.color},
		); failure != "" {
			return failure
		}
	}
	if command.light.has_intensity {
		if failure := apply_editor_action(
			session,
			game.Light_Set_Intensity{intensity = command.light.intensity},
		); failure != "" {
			return failure
		}
	}
	if command.light.has_range {
		if failure := apply_editor_action(
			session,
			game.Light_Set_Range{range = command.light.range},
		); failure != "" {
			return failure
		}
	}
	if command.pick {
		if failure := apply_editor_action(session, game.Palette_Pick{}); failure != "" {
			return failure
		}
	}
	if command.cancel {
		_ = apply_editor_action(session, game.Cancel{})
	}
	if command.has_place {
		if failure := apply_editor_action(
			session,
			game.Place_Object {
				prefab = command.place.prefab,
				body_mode = command.place.body,
				center = command.place.position,
				yaw_rad = command.place.yaw_deg * math.PI / 180.0,
			},
		); failure != "" {
			return failure
		}
	}
	if command.object.has_move {
		if failure := apply_editor_action(
			session,
			game.Move_Selected{center = command.object.move},
		); failure != "" {
			return failure
		}
	}
	if command.object.has_rotate {
		if failure := apply_editor_action(
			session,
			game.Rotate_Selected{degrees = command.object.rotate_deg},
		); failure != "" {
			return failure
		}
	}
	if command.input.has_turn {
		if failure := apply_editor_action(
			session,
			game.Turn{steps = command.input.turn, large = command.input.large},
		); failure != "" {
			return failure
		}
	}
	if command.input.has_wheel {
		if failure := apply_editor_action(
			session,
			game.Wheel{steps = command.input.wheel, large = command.input.large},
		); failure != "" {
			return failure
		}
	}
	if command.input.primary {
		if failure := apply_editor_action(session, game.Primary_Press{}); failure != "" {
			return failure
		}
	}
	if command.input.secondary {
		if failure := apply_editor_action(session, game.Secondary_Press{}); failure != "" {
			return failure
		}
	}
	if command.input.has_drag_move {
		if failure := apply_editor_action(
			session,
			game.Drag_Move{look_delta = command.input.drag_move},
		); failure != "" {
			return failure
		}
	}
	if command.input.drag_release {
		if failure := apply_editor_action(session, game.Primary_Release{}); failure != "" {
			return failure
		}
	}
	if command.object.delete {
		if failure := apply_editor_action(session, game.Delete_Selected{}); failure != "" {
			return failure
		}
	}
	if command.object.duplicate {
		if failure := apply_editor_action(session, game.Duplicate_Selected{}); failure != "" {
			return failure
		}
	}
	if command.object.undo {
		if failure := apply_editor_action(session, game.Undo{}); failure != "" {
			return failure
		}
	}
	if command.object.redo {
		if failure := apply_editor_action(session, game.Redo{}); failure != "" {
			return failure
		}
	}
	return ""
}

@(private)
apply_editor_action :: proc(session: ^Session, action: game.Edit_Action) -> string {
	result := game.edit_apply(
		&session.debug,
		&session.sim,
		action,
		{menu_open = session.hud.menu.open, captured = true},
	)
	if result.applied || result.reason == .No_Change {
		return ""
	}
	return format_error("%s", game.edit_reason_message(result.reason))
}
