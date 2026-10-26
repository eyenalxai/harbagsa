#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"

import game "src:game"
import "src:geometry"

@(test)
oriented_box_contains_respects_rotation :: proc(t: ^testing.T) {
	half_angle := f32(math.PI / 8.0)

	box := geometry.Box {
		center = {0, 0, 0},
		half_extents = {2, 1, 1},
		rotation = {0, 0, math.sin(half_angle), math.cos(half_angle)},
		emissive = 0,
	}
	testing.expect(t, game.oriented_box_contains(box, {0, 0, 0}))
	testing.expect(t, game.oriented_box_contains(box, {1.4, 0, 0}))
	testing.expect(t, !game.oriented_box_contains(box, {0, 0, 2.5}))
}
