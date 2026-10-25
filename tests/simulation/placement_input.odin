#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import game "src:game"

@(test)
placement_left_click_places_at_the_ghost_and_stays_armed :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	apply_expect(t, &dm, &sim, game.Palette_Select{index = 3}, "select failed")
	apply_expect(t, &dm, &sim, game.Palette_Pick{}, "pick failed")

	ghost, _ := game.debug_ghost_geometry(&dm)
	before := game.simulation_object_count(&sim)
	edit_step(&dm, &sim, {game.Primary_Press{}})

	testing.expect_value(t, game.simulation_object_count(&sim), before + 1)
	testing.expect(t, dm.placement.armed, "place disarmed the tool")
	id := dm.selected_object_id
	box := game.simulation_object_box(&sim, id)
	expect_near(t, box.center.x, ghost.center.x, 0.0001, "placed x")
	expect_near(t, box.center.y, ghost.center.y, 0.0001, "placed y")
	expect_near(t, box.center.z, ghost.center.z, 0.0001, "placed z")
}

@(test)
placement_right_click_cancels_without_placing :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)

	before := game.simulation_object_count(&sim)
	edit_step(&dm, &sim, {game.Secondary_Press{}})

	testing.expect(t, !dm.placement.armed, "right click kept the tool armed")
	testing.expect_value(t, game.simulation_object_count(&sim), before)
}

@(test)
placement_wheel_raises_the_ghost_in_quarter_metre_steps :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)

	edit_step(&dm, &sim, {game.Wheel{steps = 1}})
	expect_near(t, dm.placement.height, 0.25, 0.0001, "single wheel step")
	edit_step(&dm, &sim, {game.Wheel{steps = 1, large = true}})
	expect_near(t, dm.placement.height, 1.25, 0.0001, "large wheel step")
	edit_step(&dm, &sim, {game.Wheel{steps = -100}})
	expect_near(t, dm.placement.height, 0.0, 0.0001, "wheel floor")
}

@(test)
placement_qe_turns_the_ghost :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)

	edit_step(&dm, &sim, {game.Turn{steps = 1}})
	expect_near(t, dm.placement.yaw_degrees, 15.0, 0.0001, "right turn")
	edit_step(&dm, &sim, {game.Turn{steps = -1, large = true}})
	expect_near(t, dm.placement.yaw_degrees, 330.0, 0.0001, "large left turn")
}

@(test)
debug_mode_cancel_editing_closes_the_palette_and_disarms :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	placement_arm(t, &dm, &sim, .Crate)

	game.debug_mode_cancel_editing(&dm)

	testing.expect(t, !dm.palette.open, "cancel editing kept the palette open")
	testing.expect(t, !dm.placement.armed, "cancel editing kept the tool armed")
}

@(test)
placement_palette_blocks_world_editing :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)
	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	testing.expect(t, !dm.placement.armed, "opening the palette did not cancel placement")

	before := game.simulation_object_count(&sim)
	result := apply(&dm, &sim, game.Primary_Press{})

	testing.expect_value(t, game.simulation_object_count(&sim), before)
	testing.expect(t, dm.palette.open, "the click closed the palette")
	testing.expect(t, !result.applied, "a palette click applied a world edit")
}
