#+vet explicit-allocators
package harness

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

import "src:frame"
import "src:game"
import "src:geometry"
import "src:renderer"

Probe_Volume_Report :: struct {
	index:       int     `json:"index"`,
	name:        string  `json:"name,omitempty"`,
	min:         [3]f32  `json:"min"`,
	max:         [3]f32  `json:"max"`,
	spacing:     f32     `json:"spacing"`,
	counts:      [3]u32  `json:"counts"`,
	probe_count: int     `json:"probe_count"`,
	first_probe: int     `json:"first_probe"`,
}

Probe_Point_Report :: struct {
	box:    Maybe(int) `json:"box,omitempty"`,
	point:  [3]f32     `json:"point"`,
	volume: int        `json:"volume"`,
}

Probe_Coverage_Report :: struct {
	step:      f32                 `json:"step"`,
	samples:   int                 `json:"samples"`,
	outside:   int                 `json:"outside"`,
	fraction:  f32                 `json:"fraction"`,
	points:    []Probe_Point_Report `json:"points"`,
}

Probes_Report :: struct {
	scenario:    string                `json:"scenario,omitempty"`,
	count:       int                   `json:"count"`,
	probe_count: int                   `json:"probe_count"`,
	volumes:     []Probe_Volume_Report `json:"volumes"`,
	points:      []Probe_Point_Report  `json:"points"`,
	coverage:    Maybe(Probe_Coverage_Report) `json:"coverage,omitempty"`,
}

MAX_PROBE_POINTS :: 32
MAX_COVERAGE_POINTS :: 32
PROBE_COVERAGE_EDGE_MARGIN :: f32(0.25)
DEFAULT_COVERAGE_STEP :: f32(0.5)

@(private)
probes_report :: proc(
	scenario: string,
	extras: []frame.Scene_Probe_Volume,
	volumes: []renderer.Probe_Volume,
	points: [][3]f32,
	coverage: bool,
	step: f32,
) -> Probes_Report {
	report := Probes_Report {
		scenario   = strings.clone(scenario, context.allocator),
		count      = len(volumes),
		volumes    = make([]Probe_Volume_Report, len(volumes), context.allocator),
	}
	if len(points) > 0 {
		report.points = make([]Probe_Point_Report, len(points), context.allocator)
	} else {
		report.points = make([]Probe_Point_Report, len(volumes), context.allocator)
	}
	names := probe_volume_names(extras)
	defer delete(names, context.temp_allocator)
	first := 0
	for volume, index in volumes {
		report.volumes[index] = {
			index       = index,
			name        = names[index],
			min         = volume.min,
			max         = frame.probe_volume_high(volume),
			spacing     = volume.spacing,
			counts      = volume.counts,
			probe_count = frame.probe_volume_probe_count(volume),
			first_probe = first,
		}
		report.probe_count += frame.probe_volume_probe_count(volume)
		first += frame.probe_volume_probe_count(volume)
	}
	if len(points) > 0 {
		for point, index in points {
			report.points[index] = {point = point, volume = frame.probe_volume_owner(volumes, point)}
		}
	} else {
		for volume, index in volumes {
			centre := frame.probe_volume_centre(
				volume,
				int(volume.counts.x / 2),
				int(volume.counts.y / 2),
				int(volume.counts.z / 2),
			)
			report.points[index] = {
				point  = centre,
				volume = frame.probe_volume_owner(volumes, centre),
			}
		}
	}
	if coverage {
		report.coverage = probe_coverage(volumes, step)
	}
	return report
}

@(private)
probe_volume_names :: proc(extras: []frame.Scene_Probe_Volume) -> []string {
	names := make([]string, len(frame.PROBE_VOLUMES) + len(extras), context.temp_allocator)
	names[0] = frame.PROBE_VOLUME_NAMES[0]
	for extra, index in extras {
		if extra.name != "" {
			names[index + 1] = extra.name
		} else {
			names[index + 1] = fmt.aprintf("extra-%d", index, allocator = context.temp_allocator)
		}
	}
	copy(names[len(extras) + 1:], frame.PROBE_VOLUME_NAMES[1:])
	return names
}

@(private)
probe_coverage :: proc(volumes: []renderer.Probe_Volume, step: f32) -> Probe_Coverage_Report {
	report := Probe_Coverage_Report{step = step}
	points := make([dynamic]Probe_Point_Report, 0, MAX_COVERAGE_POINTS, context.allocator)
	boxes := game.arena_static_boxes()
	for box, box_index in boxes {
		for axis in 0 ..< 3 {
			for side in 0 ..< 2 {
				sample_probe_face(&report, &points, volumes, boxes, box, box_index, axis, side, step)
			}
		}
	}
	report.points = points[:]
	if report.samples > 0 {
		report.fraction = f32(report.outside) / f32(report.samples)
	}
	return report
}

@(private)
probe_point_hidden :: proc(point: [3]f32, boxes: []geometry.Box, skip: int) -> bool {
	for box, index in boxes {
		if index == skip {
			continue
		}
		if game.oriented_box_contains(box, point) {
			return true
		}
	}
	return false
}

// The eight box corners in the order `game.oriented_box_corners` returns them.
// Each face is one cyclic quad, so a bilinear sample stays on a rotated face.
PROBE_FACE_CORNERS := [3][2][4]int {
	{{0, 3, 7, 4}, {1, 2, 6, 5}},
	{{0, 1, 5, 4}, {3, 2, 6, 7}},
	{{0, 1, 2, 3}, {4, 5, 6, 7}},
}

@(private)
probe_lerp :: proc(a, b: [3]f32, t: f32) -> [3]f32 {
	return a + (b - a) * t
}

@(private)
probe_distance :: proc(a, b: [3]f32) -> f32 {
	delta := b - a
	return math.sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
}

@(private)
sample_probe_face :: proc(
	report: ^Probe_Coverage_Report,
	points: ^[dynamic]Probe_Point_Report,
	volumes: []renderer.Probe_Volume,
	boxes: []geometry.Box,
	box: geometry.Box,
	box_index, axis, side: int,
	step: f32,
) {
	center := [3]f32{box.center.x, box.center.y, box.center.z}
	half := [3]f32{box.half_extents.x, box.half_extents.y, box.half_extents.z}
	rotation := quaternion(
		x = box.rotation[0],
		y = box.rotation[1],
		z = box.rotation[2],
		w = box.rotation[3],
	)
	corners := game.oriented_box_corners(center, half, rotation)
	face := PROBE_FACE_CORNERS[axis][side]
	corner_0 := corners[face[0]]
	corner_1 := corners[face[1]]
	corner_2 := corners[face[2]]
	corner_3 := corners[face[3]]
	span_u := probe_distance(corner_0, corner_1)
	span_v := probe_distance(corner_0, corner_3)
	if span_u <= PROBE_COVERAGE_EDGE_MARGIN * 2 ||
	   span_v <= PROBE_COVERAGE_EDGE_MARGIN * 2 {
		return
	}
	u_count := max(int(span_u / step) + 1, 2)
	v_count := max(int(span_v / step) + 1, 2)
	for u_index in 0 ..= u_count {
		for v_index in 0 ..= v_count {
			u := f32(u_index) / f32(u_count)
			v := f32(v_index) / f32(v_count)
			if min(u, 1 - u) * span_u < PROBE_COVERAGE_EDGE_MARGIN ||
			   min(v, 1 - v) * span_v < PROBE_COVERAGE_EDGE_MARGIN {
				continue
			}
			top := probe_lerp(corner_0, corner_1, u)
			bottom := probe_lerp(corner_3, corner_2, u)
			point := probe_lerp(top, bottom, v)
			// The covered set is the surfaces the camera can see from inside the
			// arena. The outside of the arena walls, the floor underside, and a
			// box face that lies on the floor are not gaps when no volume owns
			// them.
			if point.x < -game.ARENA_HALF_SIZE || point.x > game.ARENA_HALF_SIZE ||
			   point.z < -game.ARENA_HALF_SIZE || point.z > game.ARENA_HALF_SIZE ||
			   point.y < 0 || point.y > game.ARENA_WALL_HEIGHT {
				continue
			}
			if axis == 1 && side == 0 && point.y <= 0.001 {
				continue
			}
			if probe_point_hidden(point, boxes, box_index) {
				continue
			}
			owner := frame.probe_volume_owner(volumes, point)
			report.samples += 1
			if owner >= 0 {
				continue
			}
			report.outside += 1
			if len(points) < MAX_COVERAGE_POINTS {
				entry := Probe_Point_Report{point = point, volume = owner}
				entry.box = box_index
				append(points, entry)
			}
		}
	}
}

@(private)
probes_report_destroy :: proc(report: ^Probes_Report, allocator: mem.Allocator) {
	if report.scenario != "" {
		delete(report.scenario, allocator)
	}
	delete(report.volumes, allocator)
	delete(report.points, allocator)
	if coverage, has := report.coverage.?; has {
		delete(coverage.points, allocator)
	}
	report^ = {}
}

