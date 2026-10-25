#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:game"

@(private)
apply :: proc(
	debug: ^game.Debug_Mode,
	sim: ^game.Simulation,
	action: game.Edit_Action,
) -> game.Edit_Result {
	return game.edit_apply(debug, sim, action, {captured = true})
}

@(private)
apply_expect :: proc(
	t: ^testing.T,
	debug: ^game.Debug_Mode,
	sim: ^game.Simulation,
	action: game.Edit_Action,
	message := "edit failed",
) {
	result := apply(debug, sim, action)
	testing.expectf(t, result.applied, "%s: %s", message, game.edit_reason_message(result.reason))
}
