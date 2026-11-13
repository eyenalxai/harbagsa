#+vet explicit-allocators
package uiaction

import "src:game"
import "src:renderer"
import "src:ui"

// Context is the game state one flat Rune action can touch. The caller owns
// every pointer; the helper never reaches into a loop or a session.
Context :: struct {
	sim:      ^game.Simulation,
	debug:    ^game.Debug_Mode,
	menu:     ^game.Menu_State,
	captured: bool,
}

Result :: struct {
	handled:        bool,
	applied:        bool,
	closed_menu:    bool,
	window_changed: bool,
	reason:         game.Edit_Reason,
}

// apply maps one flat Rune action to the game action it names. The main loop
// and the harness both call this, so a UI action has one apply path.
apply :: proc(ctx: Context, action: renderer.Ui_Action) -> Result {
	#partial switch renderer.UI_Action_Kind(action.kind) {
	case .Close_Menu:
		if ctx.menu.open {
			game.menu_close(ctx.menu)
			return {handled = true, applied = true, closed_menu = true}
		}
		return {handled = true, applied = true}
	case .Debug_Inspector:
		if ctx.menu.open {
			return edit_result(game.edit_fail(.Menu_Open))
		}
		if !ctx.debug.active {
			game.debug_mode_toggle(ctx.debug, ctx.sim)
		}
		result := game.editor_set_inspector(&ctx.debug.editor, true)
		return edit_result(result)
	case .Toggle_Inspector:
		return apply_edit(ctx, game.Inspector_Toggle{})
	case .Palette_Select:
		return apply_edit(ctx, game.Palette_Select{index = int(action.value)})
	case .Palette_Pick:
		return apply_edit(ctx, game.Palette_Pick{})
	case .Palette_Close:
		return apply_edit(ctx, game.Palette_Close{})
	case .Settings_Set:
		return apply_settings(ctx, action)
	case .Type_Weight_Set:
		return apply_type_weight(ctx, action)
	case .Physics_Debug:
		return apply_physics_debug(ctx, action)
	case .Object_Set:
		return apply_object_set(ctx, action)
	case .Object_Toggle:
		return apply_object_toggle(ctx, action)
	case .Object_Duplicate:
		if _, ok := selected_object(ctx, action.id); !ok {
			return edit_result(game.edit_fail(.No_Selection))
		}
		return apply_edit(ctx, game.Duplicate_Selected{})
	case .Object_Delete:
		if _, ok := selected_object(ctx, action.id); !ok {
			return edit_result(game.edit_fail(.No_Selection))
		}
		return apply_edit(ctx, game.Delete_Selected{})
	case .Lamp_Set:
		return apply_lamp_set(ctx, action)
	case .Lamp_Kind:
		return apply_lamp_edit(ctx, action, game.Light_Set_Kind{kind = game.Lamp_Kind(action.value)})
	case .Lamp_Color:
		return apply_lamp_edit(ctx, action, game.Light_Set_Color{color = game.Light_Color(action.value)})
	}
	return {}
}

@(private)
apply_settings :: proc(ctx: Context, action: renderer.Ui_Action) -> Result {
	id := renderer.UI_Settings_Id(action.id)
	window_changed := id == .Window_Mode || id == .Display || id == .Resolution
	game.menu_clear_status(ctx.menu)
	changed := game.settings_set(
		&ctx.sim.settings,
		game.Settings_Id(action.id),
		int(action.value),
		action.scalar,
	)
	return {
		handled = true,
		applied = changed,
		window_changed = changed && window_changed,
		reason = changed ? .None : .No_Change,
	}
}

@(private)
apply_type_weight :: proc(ctx: Context, action: renderer.Ui_Action) -> Result {
	weight := clamp(action.scalar, ui.TYPE_WEIGHT_MIN, ui.TYPE_WEIGHT_MAX)
	if weight == ctx.sim.settings.type_weight {
		return edit_result(game.edit_no_change())
	}
	ctx.sim.settings.type_weight = weight
	return edit_result(game.edit_ok())
}

@(private)
apply_physics_debug :: proc(ctx: Context, action: renderer.Ui_Action) -> Result {
	next := action.value != 0
	if next == ctx.debug.physics_debug {
		return edit_result(game.edit_no_change())
	}
	ctx.debug.physics_debug = next
	return edit_result(game.edit_ok())
}

@(private)
apply_object_set :: proc(ctx: Context, action: renderer.Ui_Action) -> Result {
	if _, ok := selected_object(ctx, action.id); !ok {
		return edit_result(game.edit_fail(.No_Selection))
	}
	switch renderer.UI_Object_Field(action.value) {
	case .Body:
		mode: game.Body_Mode = .Static
		if action.scalar >= 0.5 {
			mode = .Dynamic
		}
		return apply_edit(ctx, game.Set_Body{mode = mode})
	case .Yaw:
		return apply_edit(ctx, game.Set_Selected_Yaw{degrees = action.scalar})
	}
	return {}
}

@(private)
apply_object_toggle :: proc(ctx: Context, action: renderer.Ui_Action) -> Result {
	if _, ok := selected_object(ctx, action.id); !ok {
		return edit_result(game.edit_fail(.No_Selection))
	}
	if renderer.UI_Object_Field(action.value) == .Body {
		return apply_edit(ctx, game.Flip_Body{})
	}
	return {}
}

@(private)
apply_lamp_set :: proc(ctx: Context, action: renderer.Ui_Action) -> Result {
	switch renderer.UI_Lamp_Field(action.value) {
	case .Intensity:
		return apply_lamp_edit(ctx, action, game.Light_Set_Intensity{intensity = action.scalar})
	case .Range:
		return apply_lamp_edit(ctx, action, game.Light_Set_Range{range = action.scalar})
	case .Kind, .Color:
		return {}
	}
	return {}
}

@(private)
apply_lamp_edit :: proc(ctx: Context, action: renderer.Ui_Action, edit: game.Edit_Action) -> Result {
	if _, ok := selected_object(ctx, action.id); !ok {
		return edit_result(game.edit_fail(.No_Selection))
	}
	return apply_edit(ctx, edit)
}

@(private)
selected_object :: proc(ctx: Context, id: u32) -> (game.Object_Id, bool) {
	selected, ok := game.editor_selected_object_id(&ctx.debug.editor, ctx.sim)
	if !ok {
		return game.INVALID_OBJECT_ID, false
	}
	if id != 0 && selected != game.Object_Id(id) {
		return game.INVALID_OBJECT_ID, false
	}
	return selected, true
}

@(private)
apply_edit :: proc(ctx: Context, action: game.Edit_Action) -> Result {
	result := game.editor_apply(
		&ctx.debug.editor,
		ctx.sim,
		action,
		{
			active = ctx.debug.active,
			menu_open = ctx.menu.open,
			captured = ctx.captured,
			camera = ctx.debug.camera,
		},
	)
	return edit_result(result)
}

@(private)
edit_result :: proc(result: game.Edit_Result) -> Result {
	return {
		handled = true,
		applied = result.applied || result.reason == .No_Change,
		reason = result.reason,
	}
}
