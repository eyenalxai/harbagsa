#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests read the probe map
package frame

import "core:mem"
import "core:strings"

import "src:game"
import "src:renderer"

// The sampler picks the first volume that contains the surface point, so the
// room volume stays first. It owns every interior surface, and an arena volume
// can add sky to the room's exterior without reaching the room.
ROOM_PROBE_SPACING :: 1.04
ROOM_PROBE_COUNTS :: [3]u32{10, 3, 10}

// A crate and a platform are not low frequency. The perimeter strips use 2 m
// cells and four layers from y=0.5, so the lowest layer is near the contact.
// The narrow east strip uses 1 m cells to keep a probe near the east wall.
SOUTH_PROBE_SPACING :: f32(2.0)
WEST_PROBE_SPACING :: f32(2.065)
EAST_PROBE_SPACING :: f32(1.0)
NORTH_PROBE_SPACING :: f32(2.0)
ROOF_PROBE_SPACING :: f32(4.0)

// The room's outer wall face. The side strips end on the inner face, so the
// wall thickness and the door threshold are owned by the strip, while the room
// volume still wins the inner face and every interior point because it is
// first. A fragment on the outer face therefore lands in the strip.
ROOM_OUTER_LOW_X :: f32(game.ARENA_ROOM_X - game.ARENA_ROOM_HALF_SIZE)
ROOM_OUTER_HIGH_X :: f32(game.ARENA_ROOM_X + game.ARENA_ROOM_HALF_SIZE)
ROOM_OUTER_LOW_Z :: f32(game.ARENA_ROOM_Z - game.ARENA_ROOM_HALF_SIZE)
ROOM_OUTER_HIGH_Z :: f32(game.ARENA_ROOM_Z + game.ARENA_ROOM_HALF_SIZE)

ARENA_PROBE_EDGE :: f32(0.05)

ARENA_LOW :: f32(-game.ARENA_HALF_SIZE)

ROOF_PROBE_COUNTS :: [3]u32{3, 1, 3}
WEST_PROBE_COUNTS :: [3]u32{13, 4, 6}
EAST_PROBE_COUNTS :: [3]u32{4, 8, 12}
SOUTH_PROBE_COUNTS :: [3]u32{20, 4, 12}
NORTH_PROBE_COUNTS :: [3]u32{20, 4, 3}

// A test scene adds its own interior volumes after the room volume and before
// the arena strips, so a placed room wins the sampler over the open-arena fill.
// The cap keeps a malformed scenario from allocating an atlas the device cannot
// hold.
MAX_SCENE_PROBE_VOLUMES :: 8
MAX_SCENE_PROBES :: 4096
SCENE_PROBE_NAME_BYTES :: 31

// The gather shader adds this to the low and high bounds, so a face exactly on
// the volume edge does not fall out after a float round trip. The probe map
// must read the same bounds or it reports a gap the renderer does not have.
PROBE_VOLUME_EDGE_EPSILON :: f32(1e-3)

// The four perimeter volumes tile the open floor and meet the room's inner
// faces, so the wall thickness belongs to the strip. The room volume is first
// and still owns the inner face. The strips overlap where one meets another.
//
// The roof volume lights the room's exterior roof. Its floor is the room
// ceiling height, and its probes sit above the roof; none of them is inside
// the room.
PROBE_VOLUMES := [6]renderer.Probe_Volume {
	{
		min = {game.ARENA_ROOM_INNER_LOW_X, 0.0, game.ARENA_ROOM_INNER_LOW_Z},
		spacing = ROOM_PROBE_SPACING,
		counts = ROOM_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {
			ROOM_OUTER_LOW_X - ARENA_PROBE_EDGE,
			game.ARENA_ROOM_HEIGHT,
			ROOM_OUTER_LOW_Z - ARENA_PROBE_EDGE,
		},
		spacing = ROOF_PROBE_SPACING,
		counts = ROOF_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {
			game.ARENA_ROOM_INNER_LOW_X -
			f32(WEST_PROBE_COUNTS.x) * WEST_PROBE_SPACING,
			-0.5,
			ROOM_OUTER_LOW_Z - ARENA_PROBE_EDGE,
		},
		spacing = WEST_PROBE_SPACING,
		counts = WEST_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {
			game.ARENA_ROOM_INNER_HIGH_X,
			-0.5,
			ROOM_OUTER_LOW_Z - ARENA_PROBE_EDGE,
		},
		spacing = EAST_PROBE_SPACING,
		counts = EAST_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {
			ARENA_LOW,
			-0.5,
			game.ARENA_ROOM_INNER_LOW_Z -
			f32(SOUTH_PROBE_COUNTS.z) * SOUTH_PROBE_SPACING,
		},
		spacing = SOUTH_PROBE_SPACING,
		counts = SOUTH_PROBE_COUNTS,
		probe_offset = 0,
	},
	{
		min = {ARENA_LOW, -0.5, game.ARENA_ROOM_INNER_HIGH_Z},
		spacing = NORTH_PROBE_SPACING,
		counts = NORTH_PROBE_COUNTS,
		probe_offset = 0,
	},
}

PROBE_VOLUME_NAMES := [6]string{"room", "roof", "west", "east", "south", "north"}

// A scene block carries the probe layout that belongs to one test scene, not
// the production arena. The session composes it with the room and arena data.
Scene_Probe_Volume :: struct {
	name:    string  `json:"name,omitempty"`,
	min:     [3]f32  `json:"min"`,
	spacing: f32     `json:"spacing"`,
	counts:  [3]u32  `json:"counts"`,
}

probe_volume_probe_count :: proc(volume: renderer.Probe_Volume) -> int {
	return int(volume.counts.x) * int(volume.counts.y) * int(volume.counts.z)
}

probe_volume_high :: proc(volume: renderer.Probe_Volume) -> [3]f32 {
	return volume.min +
	       [3]f32{f32(volume.counts.x), f32(volume.counts.y), f32(volume.counts.z)} *
	           volume.spacing
}

probe_volume_contains :: proc(volume: renderer.Probe_Volume, point: [3]f32) -> bool {
	high := probe_volume_high(volume) + PROBE_VOLUME_EDGE_EPSILON
	return(
		point.x >= volume.min.x - PROBE_VOLUME_EDGE_EPSILON &&
		point.x <= high.x &&
		point.y >= volume.min.y - PROBE_VOLUME_EDGE_EPSILON &&
		point.y <= high.y &&
		point.z >= volume.min.z - PROBE_VOLUME_EDGE_EPSILON &&
		point.z <= high.z \
	)
}

// The renderer and the probe map use the same first-match order.
probe_volume_owner :: proc(volumes: []renderer.Probe_Volume, point: [3]f32) -> int {
	for volume, index in volumes {
		if probe_volume_contains(volume, point) {
			return index
		}
	}
	return -1
}

probe_volume_centre :: proc(volume: renderer.Probe_Volume, x, y, z: int) -> [3]f32 {
	return volume.min + ([3]f32{f32(x), f32(y), f32(z)} + 0.5) * volume.spacing
}

// The extras sit after the room volume, so a placed room owns its interior,
// and before the arena strips, so the open-arena fill cannot reach it.
probe_volumes_compose :: proc(
	extras: []Scene_Probe_Volume,
	allocator: mem.Allocator,
) -> ([]renderer.Probe_Volume, string) {
	volumes := make(
		[]renderer.Probe_Volume,
		len(PROBE_VOLUMES) + len(extras),
		allocator,
	)
	volumes[0] = PROBE_VOLUMES[0]
	for extra, index in extras {
		total := int(extra.counts.x) * int(extra.counts.y) * int(extra.counts.z)
		if total == 0 || !(extra.spacing > 0) {
			delete(volumes, allocator)
			return nil, "a probe volume needs positive counts and spacing"
		}
		volumes[index + 1] = {
			min     = extra.min,
			spacing = extra.spacing,
			counts  = extra.counts,
		}
	}
	copy(volumes[len(extras) + 1:], PROBE_VOLUMES[1:])
	return volumes, ""
}

scene_probe_volumes_clone :: proc(
	specs: []Scene_Probe_Volume,
	allocator: mem.Allocator,
) -> []Scene_Probe_Volume {
	clones := make([]Scene_Probe_Volume, len(specs), allocator)
	for spec, index in specs {
		clones[index] = spec
		clones[index].name = strings.clone(spec.name, allocator)
	}
	return clones
}

scene_probe_volumes_destroy :: proc(
	specs: []Scene_Probe_Volume,
	allocator: mem.Allocator,
) {
	for spec in specs {
		if spec.name != "" {
			delete(spec.name, allocator)
		}
	}
	if specs != nil {
		delete(specs, allocator)
	}
}

scene_probe_name_valid :: proc(name: string) -> bool {
	if name == "" {
		return true
	}
	if len(name) > SCENE_PROBE_NAME_BYTES {
		return false
	}
	for character in name {
		if character >= 'a' && character <= 'z' {
			continue
		}
		if character >= 'A' && character <= 'Z' {
			continue
		}
		if character >= '0' && character <= '9' {
			continue
		}
		if character == '-' || character == '_' {
			continue
		}
		return false
	}
	return true
}
