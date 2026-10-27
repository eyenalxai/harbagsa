#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import game "src:game"

@(test)
edit_failures_name_the_reason :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	cases := []struct {
		action: game.Edit_Action,
		reason: game.Edit_Reason,
	} {
		{game.Delete_Selected{}, .No_Selection},
		{game.Placement_Place{}, .Not_Armed},
		{game.Undo{}, .Nothing_To_Undo},
		{game.Redo{}, .Nothing_To_Redo},
		{game.Palette_Select{index = game.PREFAB_COUNT}, .Bad_Index},
	}
	for value in cases {
		result := apply(&dm, &sim, value.action)
		testing.expectf(
			t,
			!result.applied && result.reason == value.reason,
			"got %v, want %v",
			result.reason,
			value.reason,
		)
		testing.expect(t, game.edit_reason_message(result.reason) != "", "the reason has no message")
	}

	id := first_object_id(&sim)
	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")
	result := apply(&dm, &sim, game.Light_Adjust{change = .Color})
	testing.expect_value(t, result.reason, game.Edit_Reason.No_Lamp)
}

@(test)
menu_open_blocks_every_edit :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	id := first_object_id(&sim)
	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")
	before := game.simulation_object_box(&sim, id)

	result := game.edit_apply(&dm, &sim, game.Move_Selected{center = {4, 1, 4}}, {menu_open = true})
	testing.expect_value(t, result.reason, game.Edit_Reason.Menu_Open)
	testing.expect_value(t, game.simulation_object_box(&sim, id).center, before.center)

	result = game.edit_apply(&dm, &sim, game.Delete_Selected{}, {menu_open = true})
	testing.expect_value(t, result.reason, game.Edit_Reason.Menu_Open)
	testing.expect_value(t, game.simulation_object_count(&sim), game.INITIAL_CRATE_COUNT)
}

@(test)
body_target_follows_the_palette_and_the_armed_tool :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	id := first_object_id(&sim)
	apply_expect(t, &dm, &sim, game.Select_Object{id = id}, "select failed")
	apply_expect(t, &dm, &sim, game.Placement_Arm{prefab = .Block}, "arm failed")
	initial_mode := game.prefab(.Crate).body_mode

	apply_expect(t, &dm, &sim, game.Flip_Body{}, "flip failed")
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Dynamic)
	object, _ := game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.body_mode, initial_mode)

	apply_expect(t, &dm, &sim, game.Placement_Cancel{}, "cancel failed")
	apply_expect(t, &dm, &sim, game.Flip_Body{}, "flip failed")
	object, _ = game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.body_mode, game.Body_Mode.Static)
}
