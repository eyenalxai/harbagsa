#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import game "src:game"

@(private)
apply :: proc(dm: ^game.Debug_Mode, sim: ^game.Simulation, action: game.Edit_Action) -> game.Edit_Result {
	return game.edit_apply(dm, sim, action, {captured = true})
}

@(private)
apply_expect :: proc(
	t: ^testing.T,
	dm: ^game.Debug_Mode,
	sim: ^game.Simulation,
	action: game.Edit_Action,
	message := "edit failed",
) {
	result := apply(dm, sim, action)
	testing.expectf(t, result.applied, "%s: %s", message, game.edit_reason_message(result.reason))
}

@(private)
editor_step :: proc(
	dm: ^game.Debug_Mode,
	sim: ^game.Simulation,
	motion: game.Debug_Motion,
	actions: []game.Edit_Action = nil,
) {
	game.debug_mode_update(dm, sim, motion, actions, false, DT)
}

@(private)
edit_step :: proc(dm: ^game.Debug_Mode, sim: ^game.Simulation, actions: []game.Edit_Action) {
	editor_step(dm, sim, {captured = true}, actions)
}
