#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import game "src:game"

@(test)
active_tool_starts_empty :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	testing.expect_value(t, game.active_tool(&dm), game.Active_Tool.None)
}

@(test)
arming_placement_closes_the_palette :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	testing.expect_value(t, game.active_tool(&dm), game.Active_Tool.Palette)

	apply_expect(t, &dm, &sim, game.Placement_Arm{prefab = .Block}, "arm failed")

	testing.expect_value(t, game.active_tool(&dm), game.Active_Tool.Placement)
	testing.expect(t, !dm.palette.open, "the palette is still open")
	testing.expect(t, dm.placement.armed, "placement is not armed")
	testing.expect_value(t, dm.placement.prefab, game.Prefab_Id.Block)
	testing.expect_value(t, game.palette_selected(dm.palette), game.Prefab_Id.Block)
}

@(test)
sun_placement_takes_the_tool :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	apply_expect(t, &dm, &sim, game.Placement_Arm{prefab = .Block}, "arm failed")
	apply_expect(t, &dm, &sim, game.Sun_Toggle{}, "sun failed")

	testing.expect_value(t, game.active_tool(&dm), game.Active_Tool.Sun)
	testing.expect(t, !dm.palette.open, "the palette is still open")
	testing.expect(t, !dm.placement.armed, "placement is still armed")
	testing.expect(t, dm.sun.active, "the sun is not active")
}

@(test)
take_tool_keeps_the_requested_tool :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	game.take_tool(&dm, .Palette)

	testing.expect(t, dm.palette.open, "take_tool closed the requested palette")
	testing.expect_value(t, game.active_tool(&dm), game.Active_Tool.Palette)
}

@(test)
cancel_walks_palette_then_sun_then_placement :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	// Force the state the old code allowed through the harness: all three
	// tools set at once. One order must win, and Cancel must follow it.
	dm.palette.open = true
	dm.sun.active = true
	dm.placement.armed = true

	apply_expect(t, &dm, &sim, game.Cancel{}, "first cancel failed")
	testing.expect(t, !dm.palette.open, "the palette did not close first")

	apply_expect(t, &dm, &sim, game.Cancel{}, "second cancel failed")
	testing.expect(t, !dm.sun.active, "the sun did not close second")

	apply_expect(t, &dm, &sim, game.Cancel{}, "third cancel failed")
	testing.expect(t, !dm.placement.armed, "placement did not close third")
	testing.expect_value(t, game.active_tool(&dm), game.Active_Tool.None)

	result := apply(&dm, &sim, game.Cancel{})
	testing.expect_value(t, result.reason, game.Edit_Reason.No_Change)
}

@(test)
world_reason_matches_the_active_tool :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	cases := []struct {
		tool:   game.Active_Tool,
		reason: game.Edit_Reason,
	} {
		{.Palette, .Palette_Open},
		{.Sun, .Sun_Active},
		{.Placement, .Placement_Armed},
	}

	for value in cases {
		dm.palette.open = value.tool == .Palette
		dm.sun.active = value.tool == .Sun
		dm.placement.armed = value.tool == .Placement
		result := apply(&dm, &sim, game.Move_Selected{center = {0, 0, 0}})
		testing.expectf(
			t,
			result.reason == value.reason,
			"tool %v gave %v, want %v",
			value.tool,
			result.reason,
			value.reason,
		)
	}
}

@(test)
cancel_editing_clears_every_tool :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	dm.palette.open = true
	dm.sun.active = true
	dm.placement.armed = true

	game.debug_mode_cancel_editing(&dm)

	testing.expect(t, !dm.palette.open, "the palette is still open")
	testing.expect(t, !dm.sun.active, "the sun is still active")
	testing.expect(t, !dm.placement.armed, "placement is still armed")
	testing.expect_value(t, game.active_tool(&dm), game.Active_Tool.None)
}
