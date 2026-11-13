#+vet explicit-allocators
package uiaction

import "src:game"
import "src:renderer"

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
	case .Toggle_Debug:
		game.debug_mode_toggle(ctx.debug, ctx.sim)
		return {handled = true, applied = true}
	case .Palette_Select:
		return apply_edit(ctx, game.Palette_Select{index = int(action.value)})
	case .Palette_Close:
		return apply_edit(ctx, game.Palette_Close{})
	case .Settings_Set:
		return apply_settings(ctx, action)
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
		applied = true,
		window_changed = changed && window_changed,
	}
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
	return {
		handled = true,
		applied = result.applied || result.reason == .No_Change,
		reason = result.reason,
	}
}
