#+vet explicit-allocators
package harness

import "core:fmt"
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
			report.points[index] = {point = centre, volume = index}
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
		rotation := quaternion(
			x = box.rotation[0],
			y = box.rotation[1],
			z = box.rotation[2],
			w = box.rotation[3],
		)
		half := game.oriented_aabb_half_extents(box.half_extents, rotation)
		if point.x > box.center.x - half.x + 0.001 &&
		   point.x < box.center.x + half.x - 0.001 &&
		   point.z > box.center.z - half.z + 0.001 &&
		   point.z < box.center.z + half.z - 0.001 &&
		   point.y >= box.center.y - half.y - 0.001 &&
		   point.y <= box.center.y + half.y + 0.001 {
			return true
		}
	}
	return false
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
	sign := f32(side * 2 - 1)
	first := (axis + 1) % 3
	second := (axis + 2) % 3
	first_span := half[first] * 2
	second_span := half[second] * 2
	if first_span <= PROBE_COVERAGE_EDGE_MARGIN * 2 ||
	   second_span <= PROBE_COVERAGE_EDGE_MARGIN * 2 {
		return
	}
	first_count := max(int(first_span / step) + 1, 2)
	second_count := max(int(second_span / step) + 1, 2)
	for first_index in 0 ..= first_count {
		for second_index in 0 ..= second_count {
			point: [3]f32
			point[axis] = center[axis] + sign * half[axis]
			point[first] = center[first] - half[first] + first_span * f32(first_index) / f32(first_count)
			point[second] = center[second] - half[second] + second_span * f32(second_index) / f32(second_count)
			first_distance := min(point[first] - (center[first] - half[first]), (center[first] + half[first]) - point[first])
			second_distance := min(point[second] - (center[second] - half[second]), (center[second] + half[second]) - point[second])
			if first_distance < PROBE_COVERAGE_EDGE_MARGIN ||
			   second_distance < PROBE_COVERAGE_EDGE_MARGIN {
				continue
			}
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

