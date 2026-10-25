#+vet explicit-allocators
package frame

import "src:game"
import "src:renderer"

// The room, its lane network, and the chamber share one volume. The bounds sit
// inside the wall faces, and the probe centres stay one metre apart.
PROBE_SPACING :: 1.04
PROBE_COUNTS :: [3]u32{10, 3, 10}

PROBE_VOLUMES := [1]renderer.Probe_Volume {
	{
		min = {game.ARENA_ROOM_INNER_LOW_X, 0.0, game.ARENA_ROOM_INNER_LOW_Z},
		spacing = PROBE_SPACING,
		counts = PROBE_COUNTS,
		probe_offset = 0,
	},
}
