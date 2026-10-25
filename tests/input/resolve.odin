#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package input_test

import "core:reflect"
import "core:testing"

import "src:game"
import "src:input"
import "src:platform"

@(private)
focus :: proc(
	menu_open := false,
	debug_active := false,
	tool := game.Active_Tool.None,
	captured := true,
	pointer_available := false,
	dragging := false,
) -> input.Focus {
	return {
		game = {
			menu_open = menu_open,
			debug_active = debug_active,
			tool = tool,
			dragging = dragging,
		},
		captured = captured,
		pointer_available = pointer_available,
	}
}

@(private)
resolve_edge :: proc(
	r: ^input.Resolver,
	key: platform.Key,
	mods: platform.Modifiers,
	f: input.Focus,
	hit := input.Palette_Hit{},
) -> input.Frame_Input {
	events := platform.Events {
		captured = f.captured,
		key_count = 1,
	}
	events.keys[0] = {key, mods}
	return input.resolve(r, events, f, hit)
}

@(private)
expect_action :: proc(t: ^testing.T, frame: input.Frame_Input, want: typeid) {
	testing.expectf(t, frame.action_count == 1, "action count %d, want 1", frame.action_count)
	if frame.action_count == 0 {
		return
	}
	testing.expectf(
		t,
		reflect.union_variant_typeid(frame.actions[0]) == want,
		"unexpected action variant",
	)
}

@(test)
tab_opens_and_closes_the_palette :: proc(t: ^testing.T) {
	r: input.Resolver
	open := resolve_edge(&r, .Tab, {}, focus(debug_active = true))
	expect_action(t, open, game.Palette_Open)
	testing.expect(t, open.want_cursor_free, "an open palette must free the cursor")

	close := resolve_edge(&r, .Tab, {}, focus(debug_active = true, tool = .Palette))
	expect_action(t, close, game.Palette_Close)
	testing.expect(t, !close.want_cursor_free, "a closed palette must capture the cursor")
}

@(test)
escape_closes_the_tool_before_the_menu :: proc(t: ^testing.T) {
	r: input.Resolver
	tool := resolve_edge(&r, .Escape, {}, focus(debug_active = true, tool = .Palette))
	expect_action(t, tool, game.Cancel)
	testing.expect(t, !tool.view.menu_toggle, "Esc opened the menu and closed a tool")

	menu := resolve_edge(&r, .Escape, {}, focus())
	testing.expect_value(t, menu.action_count, 0)
	testing.expect(t, menu.view.menu_toggle, "Esc did not reach the menu")
}

@(test)
menu_owns_the_frame_while_open :: proc(t: ^testing.T) {
	r: input.Resolver
	f := focus(menu_open = true, captured = false)
	up := resolve_edge(&r, .Up, {}, f)
	testing.expect(t, up.menu.up, "Up did not reach the menu")
	testing.expect_value(t, up.action_count, 0)
	testing.expect_value(t, up.snapshot.jump_pressed, false)

	tab := resolve_edge(&r, .Tab, {}, f)
	testing.expect_value(t, tab.action_count, 0)
	space := resolve_edge(&r, .Space, {}, f)
	testing.expect_value(t, space.snapshot.jump_pressed, false)
	view := resolve_edge(&r, .F1, {}, f)
	testing.expect(t, !view.view.debug_view, "F1 worked while the menu was open")

	perf := resolve_edge(&r, .F4, {}, f)
	testing.expect(t, perf.view.perf, "F4 must work while the menu is open")
}

@(test)
player_jump_latches_and_survives_a_frame :: proc(t: ^testing.T) {
	r: input.Resolver
	f := focus()
	first := resolve_edge(&r, .Space, {}, f)
	testing.expect(t, first.snapshot.jump_pressed, "Space did not latch a jump")

	second := input.resolve(&r, {captured = true}, f, {})
	testing.expect(t, second.snapshot.jump_pressed, "the latch did not survive a frame")

	input.clear_latches(&r)
	third := input.resolve(&r, {captured = true}, f, {})
	testing.expect(t, !third.snapshot.jump_pressed, "the latch survived a step")

	free := resolve_edge(&r, .Space, {}, focus(captured = false))
	testing.expect(t, !free.snapshot.jump_pressed, "a free cursor latched a jump")

	debug := resolve_edge(&r, .Space, {}, focus(debug_active = true))
	testing.expect(t, !debug.snapshot.jump_pressed, "debug mode latched a jump")
}

@(test)
sprint_and_prone_latches_gate_on_capture :: proc(t: ^testing.T) {
	r: input.Resolver
	sprint := resolve_edge(&r, .LShift, {}, focus())
	testing.expect(t, sprint.snapshot.sprint_pressed, "Shift did not latch sprint")

	input.clear_latches(&r)
	prone := resolve_edge(&r, .Z, {}, focus())
	testing.expect(t, prone.snapshot.prone_pressed, "Z did not latch prone")

	input.clear_latches(&r)
	ctrl_z := resolve_edge(&r, .Z, {.Ctrl}, focus())
	testing.expect(t, !ctrl_z.snapshot.prone_pressed, "Ctrl+Z latched prone in play")
}

@(test)
light_keys_are_blocked_by_the_palette_and_sun :: proc(t: ^testing.T) {
	r: input.Resolver
	palette := resolve_edge(&r, .C, {}, focus(debug_active = true, tool = .Palette))
	testing.expect_value(t, palette.action_count, 0)

	sun := resolve_edge(&r, .C, {}, focus(debug_active = true, tool = .Sun))
	testing.expect_value(t, sun.action_count, 0)

	world := resolve_edge(&r, .C, {}, focus(debug_active = true))
	expect_action(t, world, game.Light_Adjust)

	placement := resolve_edge(&r, .C, {}, focus(debug_active = true, tool = .Placement))
	expect_action(t, placement, game.Light_Adjust)
}

@(test)
placement_turn_is_allowed_while_armed_and_blocked_by_the_palette :: proc(t: ^testing.T) {
	r: input.Resolver
	turn := resolve_edge(&r, .Q, {}, focus(debug_active = true, tool = .Placement))
	testing.expect_value(t, turn.action_count, 1)
	value, ok := turn.actions[0].(game.Turn)
	testing.expect(t, ok, "Q did not add a Turn")
	testing.expect_value(t, value.steps, -1)
	testing.expect(t, !value.large, "a plain Q became a large turn")

	large := resolve_edge(&r, .Q, {.Shift}, focus(debug_active = true, tool = .Placement))
	value, ok = large.actions[0].(game.Turn)
	testing.expect(t, ok, "Shift+Q did not add a Turn")
	testing.expect(t, value.large, "Shift+Q was not a large turn")

	palette := resolve_edge(&r, .Q, {}, focus(debug_active = true, tool = .Palette))
	testing.expect_value(t, palette.action_count, 0)
}

@(test)
palette_right_click_closes_without_a_world_press :: proc(t: ^testing.T) {
	r: input.Resolver
	events := platform.Events {
		captured = true,
		secondary_pressed = true,
	}
	frame := input.resolve(
		&r,
		events,
		focus(debug_active = true, tool = .Palette, pointer_available = true),
		{card = 2, inside = true},
	)
	expect_action(t, frame, game.Palette_Close)
}

@(test)
palette_pointer_selects_and_closes :: proc(t: ^testing.T) {
	r: input.Resolver
	events := platform.Events {
		captured = true,
		pointer_pressed = true,
	}
	hover := input.resolve(
		&r,
		{captured = true, pointer_moved = true},
		focus(debug_active = true, tool = .Palette, pointer_available = true),
		{card = 2, inside = true},
	)
	expect_action(t, hover, game.Palette_Select)
	value, ok := hover.actions[0].(game.Palette_Select)
	testing.expect(t, ok, "hover was not a Palette_Select")
	testing.expect_value(t, value.index, 2)

	click := input.resolve(
		&r,
		events,
		focus(debug_active = true, tool = .Palette, pointer_available = true),
		{card = 2, inside = true},
	)
	testing.expect_value(t, click.action_count, 2)
	testing.expect(t, click.want_cursor_free == false, "a pick kept the cursor free")

	outside := input.resolve(
		&r,
		{captured = true, pointer_pressed = true},
		focus(debug_active = true, tool = .Palette, pointer_available = true),
		{card = -1, inside = false},
	)
	expect_action(t, outside, game.Palette_Close)
}

@(test)
reset_and_view_keys_fill_the_intents :: proc(t: ^testing.T) {
	r: input.Resolver
	reset := resolve_edge(&r, .R, {}, focus())
	testing.expect(t, reset.view.reset_player, "R did not ask for a player reset")
	testing.expect(t, !reset.view.reset_scene, "R asked for a scene reset")

	scene := resolve_edge(&r, .R, {.Shift}, focus())
	testing.expect(t, scene.view.reset_scene, "Shift+R did not ask for a scene reset")

	views := resolve_edge(&r, .F1, {}, focus())
	testing.expect(t, views.view.debug_view, "F1 did not ask for the debug view")
	views = resolve_edge(&r, .F2, {}, focus())
	testing.expect(t, views.view.debug_mode, "F2 did not ask for debug mode")
	views = resolve_edge(&r, .F3, {}, focus())
	testing.expect(t, views.view.taa, "F3 did not ask for TAA")
	views = resolve_edge(&r, .F4, {}, focus())
	testing.expect(t, views.view.perf, "F4 did not ask for perf")
	views = resolve_edge(&r, .F5, {}, focus())
	testing.expect(t, views.view.repro, "F5 did not ask for a repro")
}

@(test)
debug_keys_are_gated_by_the_debug_mode :: proc(t: ^testing.T) {
	r: input.Resolver
	for key in ([8]platform.Key{.Tab, .Q, .E, .M, .G, .L, .Delete, .X}) {
		frame := resolve_edge(&r, key, {}, focus())
		testing.expectf(t, frame.action_count == 0, "%v acted outside debug mode", key)
	}

	dup := resolve_edge(&r, .D, {.Ctrl}, focus())
	testing.expect_value(t, dup.action_count, 0)
}

@(test)
undo_and_redo_share_z_with_ctrl :: proc(t: ^testing.T) {
	r: input.Resolver
	undo := resolve_edge(&r, .Z, {.Ctrl}, focus(debug_active = true))
	expect_action(t, undo, game.Undo)
	redo := resolve_edge(&r, .Z, {.Ctrl, .Shift}, focus(debug_active = true))
	expect_action(t, redo, game.Redo)
	dup := resolve_edge(&r, .D, {.Ctrl}, focus(debug_active = true))
	expect_action(t, dup, game.Duplicate_Selected)
}

@(test)
motion_and_look_are_gated_by_the_frame :: proc(t: ^testing.T) {
	r: input.Resolver
	events := platform.Events {
		captured = true,
		move_forward = 1,
		move_right = -1,
		fly_up = true,
		look_delta = {3, 4},
	}
	player := input.resolve(&r, events, focus(), {})
	testing.expect_value(t, player.snapshot.move_forward, f32(1))
	testing.expect_value(t, player.snapshot.move_right, f32(-1))
	testing.expect_value(t, player.look_delta, [2]f32{3, 4})

	free := input.resolve(&r, events, focus(captured = false), {})
	testing.expect_value(t, free.snapshot.move_forward, f32(0))
	testing.expect_value(t, free.look_delta, [2]f32{0, 0})

	debug := input.resolve(&r, events, focus(debug_active = true), {})
	testing.expect_value(t, debug.snapshot.move_forward, f32(0))
	testing.expect_value(t, debug.motion.move_up, f32(1))
	testing.expect_value(t, debug.motion.look_delta, [2]f32{3, 4})
}

@(test)
wheel_rounds_and_only_acts_without_a_tool :: proc(t: ^testing.T) {
	r: input.Resolver
	events := platform.Events {
		captured = true,
		wheel_delta = 1.6,
	}
	events.sprint_held = true
	frame := input.resolve(&r, events, focus(debug_active = true), {})
	testing.expect_value(t, frame.action_count, 1)
	value, ok := frame.actions[0].(game.Wheel)
	testing.expect(t, ok, "the wheel did not add a Wheel")
	testing.expect_value(t, value.steps, 2)
	testing.expect(t, value.large, "the wheel ignored Shift")

	palette := input.resolve(
		&r,
		events,
		focus(debug_active = true, tool = .Palette),
		{},
	)
	testing.expect_value(t, palette.action_count, 0)
}

@(test)
drag_move_only_runs_while_dragging :: proc(t: ^testing.T) {
	r: input.Resolver
	events := platform.Events {
		captured = true,
		look_delta = {5, 0},
	}
	idle := input.resolve(&r, events, focus(debug_active = true), {})
	testing.expect_value(t, idle.action_count, 0)

	drag := input.resolve(&r, events, focus(debug_active = true, dragging = true), {})
	testing.expect_value(t, drag.action_count, 1)
	value, ok := drag.actions[0].(game.Drag_Move)
	testing.expect(t, ok, "the drag did not add a Drag_Move")
	testing.expect_value(t, value.look_delta, [2]f32{5, 0})
}
