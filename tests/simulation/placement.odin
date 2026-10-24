#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"

import b3 "libs:box3d"
import game "src:game"

PLACEMENT_FLOOR_PITCH :: -0.9
PLACEMENT_SKY_PITCH :: 0.6

@(private)
placement_setup :: proc(t: ^testing.T) -> (game.Simulation, game.Debug_Mode) {
	sim, dm := object_editor_setup(t)
	dm.camera.pitch = PLACEMENT_FLOOR_PITCH
	return sim, dm
}

@(private)
placement_arm :: proc(t: ^testing.T, dm: ^game.Debug_Mode, sim: ^game.Simulation, id: game.Prefab_Id) {
	testing.expectf(t, game.debug_placement_arm(dm, sim, id), "arm %v failed", id)
}

@(test)
palette_pick_arms_the_selected_prefab :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)

	game.debug_palette_open(&dm)
	testing.expect(t, dm.palette.open, "palette did not open")
	testing.expect(t, game.debug_palette_select(&dm, 4), "platform select failed")
	testing.expect(t, game.debug_palette_pick(&dm, &sim), "pick failed")

	testing.expect(t, !dm.palette.open, "pick left the palette open")
	testing.expect(t, dm.placement.armed, "pick did not arm the placement")
	testing.expect_value(t, dm.placement.prefab, game.Prefab_Id.Platform)
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)
}

@(test)
palette_body_defaults_from_the_prefab_and_sticks_until_changed :: proc(t: ^testing.T) {
	dm := game.debug_mode_create()
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Dynamic)

	game.debug_palette_flip_body(&dm)
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)
	testing.expect(t, game.debug_palette_select(&dm, 5), "ramp select failed")
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)

	testing.expect(t, game.debug_palette_select(&dm, 0), "crate select failed")
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Dynamic)
	game.debug_palette_flip_body(&dm)
	testing.expect(t, game.debug_palette_select(&dm, 0), "repeat select failed")
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)
	testing.expect(t, !game.debug_palette_select(&dm, game.PREFAB_COUNT), "bad index accepted")
}

@(test)
placement_ray_puts_the_aabb_bottom_on_the_hit :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Block)

	anchor := dm.placement.anchor
	expect_near(t, anchor.y, 0.0, 0.001, "ray did not hit the floor")
	ghost, ok := game.debug_ghost_geometry(&dm)
	testing.expect(t, ok, "armed ghost has no geometry")
	expect_near(t, ghost.bottom.x, anchor.x, 0.0001, "bottom x")
	expect_near(t, ghost.bottom.y, anchor.y, 0.0001, "bottom y")
	expect_near(t, ghost.bottom.z, anchor.z, 0.0001, "bottom z")
	expect_near(
		t,
		ghost.center.y - ghost.bottom.y,
		game.prefab(.Block).half_extents.y,
		0.0001,
		"aabb half height",
	)
}

@(test)
placement_ray_miss_uses_the_fallback_distance :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	dm.camera.pitch = PLACEMENT_SKY_PITCH
	placement_arm(t, &dm, &sim, .Crate)

	expected := dm.camera.position +
	            game.debug_camera_forward(dm.camera) * game.PLACEMENT_FALLBACK_DISTANCE
	expect_near(t, dm.placement.anchor.x, expected.x, 0.0001, "fallback x")
	expect_near(t, dm.placement.anchor.y, expected.y, 0.0001, "fallback y")
	expect_near(t, dm.placement.anchor.z, expected.z, 0.0001, "fallback z")
}

@(test)
placement_height_steps_and_clamps_to_the_surface :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)

	game.debug_placement_raise(&dm, 1, false)
	expect_near(t, dm.placement.height, 0.25, 0.0001, "single height step")
	game.debug_placement_raise(&dm, 1, true)
	expect_near(t, dm.placement.height, 1.25, 0.0001, "large height step")

	game.debug_placement_raise(&dm, -100, true)
	expect_near(t, dm.placement.height, 0.0, 0.0001, "height floor")
	ghost, _ := game.debug_ghost_geometry(&dm)
	testing.expect(t, ghost.bottom.y >= ghost.surface.y, "ghost sank below its surface")
}

@(test)
placement_yaw_steps_fifteen_and_forty_five_degrees :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)

	game.debug_placement_turn(&dm, 1, false)
	expect_near(t, dm.placement.yaw_degrees, 15.0, 0.0001, "yaw step")
	game.debug_placement_turn(&dm, 1, true)
	expect_near(t, dm.placement.yaw_degrees, 60.0, 0.0001, "large yaw step")
	game.debug_placement_turn(&dm, -4, false)
	expect_near(t, dm.placement.yaw_degrees, 0.0, 0.0001, "yaw back to zero")
	game.debug_placement_turn(&dm, -1, false)
	expect_near(t, dm.placement.yaw_degrees, 345.0, 0.0001, "yaw wrap")
}

@(test)
placement_rotation_composes_yaw_and_base_pitch :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Ramp)
	game.debug_placement_set_yaw(&dm, 90.0)

	ghost, _ := game.debug_ghost_geometry(&dm)
	expected := b3.MulQuat(
		b3.MakeQuatFromAxisAngle({0.0, 1.0, 0.0}, math.PI * 0.5),
		b3.MakeQuatFromAxisAngle({1.0, 0.0, 0.0}, game.RAMP_BASE_PITCH),
	)
	expect_near(t, ghost.rotation.x, expected.x, 0.0001, "rotation x")
	expect_near(t, ghost.rotation.y, expected.y, 0.0001, "rotation y")
	expect_near(t, ghost.rotation.z, expected.z, 0.0001, "rotation z")
	expect_near(t, ghost.rotation.w, expected.w, 0.0001, "rotation w")
}

@(test)
placement_snap_rounds_the_bottom_to_a_quarter_metre_grid :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Block)
	testing.expect(t, !dm.placement.snap, "snap must start off")
	dm.placement.anchor = {0.13, 0.0, 11.37}
	dm.placement.height = 0.7
	game.debug_placement_toggle_snap(&dm)
	testing.expect(t, dm.placement.snap, "snap toggle did not turn on")

	ghost, _ := game.debug_ghost_geometry(&dm)
	expect_near(t, ghost.bottom.x, 0.25, 0.0001, "snapped x")
	expect_near(t, ghost.bottom.z, 11.25, 0.0001, "snapped z")
	expect_near(t, ghost.bottom.y, 0.7, 0.0001, "snap must not move the height")

	game.debug_placement_set_snap(&dm, false)
	ghost, _ = game.debug_ghost_geometry(&dm)
	expect_near(t, ghost.bottom.x, 0.13, 0.0001, "unsnapped x")
	expect_near(t, ghost.bottom.z, 11.37, 0.0001, "unsnapped z")
}

@(test)
placement_place_creates_at_the_ghost_and_stays_armed :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	game.debug_palette_select(&dm, 3)
	testing.expect(t, game.debug_palette_pick(&dm, &sim), "pick failed")
	game.debug_placement_set_yaw(&dm, 30.0)
	game.debug_placement_set_height(&dm, 0.5)

	ghost, _ := game.debug_ghost_geometry(&dm)
	before := game.simulation_object_count(&sim)
	id := game.debug_placement_place(&dm, &sim)
	testing.expect(t, id != game.INVALID_OBJECT_ID, "place failed")
	testing.expect_value(t, game.simulation_object_count(&sim), before + 1)

	object, found := game.simulation_object_find(&sim, id)
	testing.expect(t, found, "placed object is not findable")
	testing.expect_value(t, object.prefab, game.Prefab_Id.Block)
	testing.expect_value(t, object.body_mode, game.Body_Mode.Static)
	box := game.simulation_object_box(&sim, id)
	expect_near(t, box.center.x, ghost.center.x, 0.0001, "placed x")
	expect_near(t, box.center.y, ghost.center.y, 0.0001, "placed y")
	expect_near(t, box.center.z, ghost.center.z, 0.0001, "placed z")
	expect_near(t, game.simulation_object_yaw(&sim, id), math.PI / 6.0, 0.01, "placed yaw")

	testing.expect(t, dm.placement.armed, "place disarmed the tool")
	testing.expect_value(t, dm.selected_object_id, id)
}

@(test)
placement_at_capacity_is_a_no_op :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	for game.simulation_object_count(&sim) < game.MAX_PLACED_OBJECTS {
		_ = game.simulation_create_object(
			&sim,
			{prefab = .Block, body_mode = .Static, center = {0.0, -5.0, 0.0}, yaw = 0.0},
		)
	}
	placement_arm(t, &dm, &sim, .Crate)
	dm.selection = .Object
	dm.selected_object_id = 1

	id := game.debug_placement_place(&dm, &sim)
	testing.expect_value(t, id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, game.simulation_object_count(&sim), game.MAX_PLACED_OBJECTS)
	testing.expect_value(t, dm.selection, game.Debug_Selection.Object)
	testing.expect_value(t, dm.selected_object_id, game.Object_Id(1))
	testing.expect(t, dm.placement.armed, "a rejected place disarmed the tool")
}

@(test)
placement_cancel_clears_the_armed_tool :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)
	before := game.simulation_object_count(&sim)

	game.debug_placement_cancel(&dm)
	testing.expect(t, !dm.placement.armed, "cancel kept the tool armed")
	testing.expect_value(t, game.simulation_object_count(&sim), before)
	testing.expect_value(t, game.debug_placement_place(&dm, &sim), game.INVALID_OBJECT_ID)
}

@(test)
placement_ghost_lines_draw_the_outline_footprint_and_height_guide :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Block)
	game.debug_placement_set_height(&dm, 0.5)

	lines: game.Debug_Lines
	game.collect_placement_lines(&dm, &lines)
	testing.expect_value(t, lines.count, 17)

	game.debug_placement_cancel(&dm)
	lines.count = 0
	game.collect_placement_lines(&dm, &lines)
	testing.expect_value(t, lines.count, 0)
}

@(test)
editor_lines_include_the_armed_ghost :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.simulation_destroy(&sim)

	lines: game.Debug_Lines
	game.collect_editor_lines(&dm, &sim, &lines)
	base := lines.count
	placement_arm(t, &dm, &sim, .Block)
	game.debug_placement_set_height(&dm, 0.5)
	lines.count = 0
	game.collect_editor_lines(&dm, &sim, &lines)
	testing.expect_value(t, lines.count, base + 17)
}
