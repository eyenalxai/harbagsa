#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(private)
place_lamp :: proc(
	t: ^testing.T,
	sim: ^game.Simulation,
	dm: ^game.Debug_Mode,
	center: b3.Vec3,
) -> game.Object_Id {
	apply_expect(t, dm, sim, game.Place_Object {
		prefab = .Lamp,
		body_mode = .Static,
		center = center,
		yaw_rad = 0,
	}, "lamp did not place")
	return dm.selected_object_id
}

@(test)
lamp_placement_sticks_until_the_prefab_changes :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	apply_expect(t, &dm, &sim, game.Palette_Select{index = int(game.Prefab_Id.Lamp)}, "select failed")
	testing.expect_value(t, dm.palette.light.color, game.Light_Color.Warm)

	apply_expect(t, &dm, &sim, game.Light_Adjust{change = .Color}, "colour change failed")
	apply_expect(t, &dm, &sim, game.Light_Adjust{change = .Intensity_Up}, "intensity change failed")
	apply_expect(t, &dm, &sim, game.Light_Adjust{change = .Intensity_Up}, "intensity change failed")
	apply_expect(t, &dm, &sim, game.Light_Adjust{change = .Range_Up}, "range change failed")
	apply_expect(t, &dm, &sim, game.Light_Adjust{change = .Range_Up}, "range change failed")
	testing.expect_value(t, dm.palette.light.color, game.Light_Color.Cool)
	expect_near(t, dm.palette.light.intensity, 1.9, 0.0001, "tuned intensity")
	expect_near(t, dm.palette.light.range, 10.0, 0.0001, "tuned range")

	first := place_lamp(t, &sim, &dm, {2, 0.25, 9})
	second := place_lamp(t, &sim, &dm, {4, 0.25, 9})
	placed := [2]game.Object_Id{first, second}
	for id in placed {
		object, found := game.simulation_object_find(&sim, id)
		testing.expect(t, found, "lamp did not place")
		testing.expect_value(t, object.light.color, game.Light_Color.Cool)
		expect_near(t, object.light.intensity, 1.9, 0.0001, "placed intensity")
		expect_near(t, object.light.range, 10.0, 0.0001, "placed range")
		testing.expect_value(
			t,
			game.simulation_object_box(&sim, id).color,
			game.light_color4(game.Light_Color.Cool),
		)
		testing.expect(t, game.simulation_object_box(&sim, id).emissive > 0, "lamp is not emissive")
	}

	apply_expect(t, &dm, &sim, game.Palette_Select{index = int(game.Prefab_Id.Crate)}, "crate select failed")
	apply_expect(t, &dm, &sim, game.Palette_Select{index = int(game.Prefab_Id.Lamp)}, "lamp select failed")
	testing.expect_value(t, dm.palette.light.color, game.Light_Color.Warm)
	expect_near(t, dm.palette.light.intensity, 1.5, 0.0001, "default intensity restored")
	expect_near(t, dm.palette.light.range, 8.0, 0.0001, "default range restored")

	third := place_lamp(t, &sim, &dm, {6, 0.25, 9})
	object, _ := game.simulation_object_find(&sim, third)
	testing.expect_value(t, object.light.color, game.Light_Color.Warm)
	expect_near(t, object.light.intensity, 1.5, 0.0001, "default placed intensity")
}

@(test)
intensity_and_range_steps_clamp_at_their_limits :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	apply_expect(t, &dm, &sim, game.Palette_Select{index = int(game.Prefab_Id.Lamp)}, "select failed")

	for _ in 0 ..< 20 {
		_ = apply(&dm, &sim, game.Light_Adjust{change = .Intensity_Down})
	}
	expect_near(t, dm.palette.light.intensity, game.LIGHT_INTENSITY_MIN, 0.0001, "intensity floor")
	for _ in 0 ..< 40 {
		_ = apply(&dm, &sim, game.Light_Adjust{change = .Intensity_Up})
	}
	expect_near(t, dm.palette.light.intensity, game.LIGHT_INTENSITY_MAX, 0.0001, "intensity ceiling")

	for _ in 0 ..< 40 {
		_ = apply(&dm, &sim, game.Light_Adjust{change = .Range_Down})
	}
	expect_near(t, dm.palette.light.range, game.LIGHT_RANGE_MIN, 0.0001, "range floor")
	for _ in 0 ..< 40 {
		_ = apply(&dm, &sim, game.Light_Adjust{change = .Range_Up})
	}
	expect_near(t, dm.palette.light.range, game.LIGHT_RANGE_MAX, 0.0001, "range ceiling")

	apply_expect(t, &dm, &sim, game.Light_Adjust{change = .Color}, "colour change failed")
	testing.expect_value(t, dm.palette.light.color, game.Light_Color.Cool)
}

@(test)
selected_lamp_edits_and_undoes_its_light :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	id := place_lamp(t, &sim, &dm, {2, 0.25, 9})
	apply_expect(t, &dm, &sim, game.Palette_Close{}, "close failed")
	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	apply_expect(t, &dm, &sim, game.Light_Adjust{change = .Color}, "colour edit failed")
	testing.expect_value(t, game.debug_history_depth(&dm), 2)
	object, _ := game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.light.color, game.Light_Color.Cool)

	apply_expect(t, &dm, &sim, game.Light_Adjust{change = .Intensity_Up}, "intensity edit failed")
	testing.expect_value(t, game.debug_history_depth(&dm), 3)
	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	object, _ = game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.light.color, game.Light_Color.Cool)
	expect_near(t, object.light.intensity, 1.5, 0.0001, "undo kept the intensity")

	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	object, _ = game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.light.color, game.Light_Color.Warm)
	apply_expect(t, &dm, &sim, game.Redo{}, "redo failed")
	object, _ = game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.light.color, game.Light_Color.Cool)
}

@(test)
non_lamp_selection_ignores_the_light_keys :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	id := first_object_id(&sim)
	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")
	testing.expect(t, !apply(&dm, &sim, game.Light_Adjust{change = .Color}).applied, "a crate accepted a light key")
	testing.expect_value(t, game.debug_history_depth(&dm), 0)

	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	apply_expect(t, &dm, &sim, game.Palette_Select{index = int(game.Prefab_Id.Block)}, "block select failed")
	testing.expect(t, !apply(&dm, &sim, game.Light_Adjust{change = .Range_Up}).applied, "a block accepted a light key")
}

@(test)
light_values_survive_a_history_restore_with_the_same_id :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	apply_expect(t, &dm, &sim, game.Palette_Select{index = int(game.Prefab_Id.Lamp)}, "lamp select failed")
	apply_expect(t, &dm, &sim, game.Light_Set_Color{color = .Blue}, "colour failed")
	apply_expect(t, &dm, &sim, game.Light_Set_Intensity{intensity = 2.6}, "intensity failed")
	apply_expect(t, &dm, &sim, game.Light_Set_Range{range = 13.0}, "range failed")
	id := place_lamp(t, &sim, &dm, {2, 0.25, 9})
	apply_expect(t, &dm, &sim, game.Palette_Close{}, "close failed")
	step_world(&sim, 30)
	before := game.simulation_object_box(&sim, id)

	apply_expect(t, &dm, &sim, game.Move_Selected{center = {5, 0.25, 9}}, "move failed")
	apply_expect(t, &dm, &sim, game.Undo{}, "undo failed")
	restored := game.simulation_object_box(&sim, id)
	testing.expect_value(t, restored.center, before.center)
	object, found := game.simulation_object_find(&sim, id)
	testing.expect(t, found, "the restore lost the id")
	testing.expect_value(t, object.light.color, game.Light_Color.Blue)
	expect_near(t, object.light.intensity, 2.6, 0.0001, "restored intensity")
	expect_near(t, object.light.range, 13.0, 0.0001, "restored range")
	testing.expect_value(t, game.simulation_object_scale(&sim, id), 1.0)
	testing.expect_value(t, game.simulation_object_spawn_age(&sim, id), 0.0)
}

@(test)
every_lamp_is_collected_in_placement_order :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	positions := []f32{1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0, 5.0, 6.0}
	ids: [10]game.Object_Id
	for x, index in positions {
		ids[index] = game.simulation_create_object(
			&sim,
			{prefab = .Lamp, body_mode = .Static, center = {x, 1.0, 0.0}, yaw_rad = 0},
		)
	}
	testing.expect_value(t, game.simulation_lamp_count(&sim), 10)
	testing.expect_value(t, game.simulation_active_light_count(&sim), 10)

	active := game.simulation_collect_lights(&sim)
	testing.expect_value(t, len(active), 10)
	for light, index in active {
		testing.expect_value(t, light.object_id, ids[index])
	}

	again := game.simulation_collect_lights(&sim)
	testing.expect_value(t, len(again), 10)
	for light, index in again {
		testing.expect_value(t, light.object_id, active[index].object_id)
	}
}
