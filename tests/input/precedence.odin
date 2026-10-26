#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package input_test

import "core:testing"

import "src:game"
import "src:input"
import "src:platform"

@(test)
light_keys_follow_the_palette_and_the_placement_tool :: proc(t: ^testing.T) {
	r: input.Resolver
	palette := resolve_edge(&r, .C, {}, focus(debug_active = true, tool = .Palette))
	expect_action(t, palette, game.Light_Adjust)

	world := resolve_edge(&r, .C, {}, focus(debug_active = true))
	expect_action(t, world, game.Light_Adjust)

	placement := resolve_edge(&r, .C, {}, focus(debug_active = true, tool = .Placement))
	expect_action(t, placement, game.Light_Adjust)
}

@(test)
tab_and_a_light_key_share_a_frame :: proc(t: ^testing.T) {
	r: input.Resolver
	frame := resolve_keys(
		&r,
		[]platform.Key_Edge{{.Tab, {}}, {.C, {}}},
		focus(debug_active = true),
	)
	testing.expect_value(t, frame.action_count, 2)
	testing.expect(t, has_action(frame, game.Palette_Open), "Tab did not open the palette")
	testing.expect(t, has_action(frame, game.Light_Adjust), "C did not tune the palette light")
}

@(test)
l_key_does_not_intercept_light_or_world_keys :: proc(t: ^testing.T) {
	r: input.Resolver
	frame := resolve_keys(
		&r,
		[]platform.Key_Edge{{.L, {}}, {.C, {}}, {.Q, {}}},
		focus(debug_active = true),
	)
	testing.expect_value(t, frame.action_count, 2)
	testing.expect(t, has_action(frame, game.Light_Adjust), "L dropped the light key")
	testing.expect(t, has_action(frame, game.Turn), "L dropped the world key")
}

@(test)
tab_and_escape_opens_the_menu :: proc(t: ^testing.T) {
	r: input.Resolver
	frame := resolve_keys(
		&r,
		[]platform.Key_Edge{{.Tab, {}}, {.Escape, {}}},
		focus(debug_active = true),
	)
	testing.expect(t, frame.view.menu_toggle, "Esc did not reach the menu")
	testing.expect(t, has_action(frame, game.Palette_Open), "Tab did not open the palette")
}

@(test)
digits_select_palette_cards :: proc(t: ^testing.T) {
	r: input.Resolver
	frame := resolve_edge(&r, .Digit_3, {}, focus(debug_active = true, tool = .Palette))
	expect_action(t, frame, game.Palette_Select)
	value, ok := frame.actions[0].(game.Palette_Select)
	testing.expect(t, ok, "a digit did not add a Palette_Select")
	testing.expect_value(t, value.index, 2)
}

@(test)
pause_reports_the_menu :: proc(t: ^testing.T) {
	r: input.Resolver
	open := input.resolve(&r, {}, focus(menu_open = true, captured = false), {})
	testing.expect(t, open.pause, "an open menu did not pause the frame")
	closed := input.resolve(&r, {}, focus(), {})
	testing.expect(t, !closed.pause, "a closed menu paused the frame")
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

