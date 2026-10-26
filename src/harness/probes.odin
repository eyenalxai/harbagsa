#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

import "src:frame"


cli_probes :: proc(args: []string) -> int {
	json_output := false
	coverage := false
	step := DEFAULT_COVERAGE_STEP
	scenario_path := ""
	points := make([dynamic][3]f32, 0, 8, context.allocator)
	defer delete(points)

	index := 0
	for index < len(args) {
		argument := args[index]
		switch {
		case argument == "--help" || argument == "-h":
			print_probes_usage()
			return EXIT_OK
		case argument == "--json":
			json_output = true
			index += 1
		case argument == "--coverage":
			coverage = true
			index += 1
		case argument == "--step":
			if index + 1 >= len(args) {
				fmt.eprintln("harbagsa-agent probes: --step needs a positive number")
				return EXIT_SCENARIO
			}
			parsed, ok := strconv.parse_f32(args[index + 1])
			if !ok || parsed < 0.1 || parsed > 100 {
				fmt.eprintln("harbagsa-agent probes: --step must be in [0.1, 100]")
				return EXIT_SCENARIO
			}
			step = parsed
			index += 2
		case argument == "--point":
			if index + 1 >= len(args) {
				fmt.eprintln("harbagsa-agent probes: --point needs X,Y,Z")
				return EXIT_SCENARIO
			}
			point, ok := parse_probe_point(args[index + 1])
			if !ok {
				fmt.eprintln("harbagsa-agent probes: --point needs X,Y,Z")
				return EXIT_SCENARIO
			}
			if len(points) >= MAX_PROBE_POINTS {
				fmt.eprintf("harbagsa-agent probes: at most %d --point values\n", MAX_PROBE_POINTS)
				return EXIT_SCENARIO
			}
			append(&points, point)
			index += 2
		case strings.has_prefix(argument, "-"):
			fmt.eprintf("harbagsa-agent probes: unknown option %q\n", argument)
			print_probes_usage()
			return EXIT_SCENARIO
		case scenario_path == "":
			scenario_path = argument
			index += 1
		case:
			fmt.eprintln("harbagsa-agent probes: probes takes at most one scenario path")
			print_probes_usage()
			return EXIT_SCENARIO
		}
	}

	extras: []frame.Scene_Probe_Volume
	if scenario_path != "" {
		loaded, load_error := probe_scenario_volumes(scenario_path, context.allocator)
		if load_error != "" {
			fmt.eprintf("harbagsa-agent probes: %s\n", load_error)
			delete(load_error, context.allocator)
			return EXIT_SCENARIO
		}
		extras = loaded
	}
	defer frame.scene_probe_volumes_destroy(extras, context.allocator)

	volumes, compose_error := frame.probe_volumes_compose(extras, context.allocator)
	if compose_error != "" {
		fmt.eprintf("harbagsa-agent probes: %s\n", compose_error)
		return EXIT_SCENARIO
	}
	defer delete(volumes, context.allocator)

	report := probes_report(scenario_path, extras, volumes, points[:], coverage, step)
	defer probes_report_destroy(&report, context.allocator)
	if json_output {
		data, marshal_error := json.marshal(report, {}, context.allocator)
		if marshal_error != nil {
			fmt.eprintln("harbagsa-agent probes: cannot encode the probe map")
			return EXIT_RENDER
		}
		defer delete(data, context.allocator)
		fmt.println(string(data))
		return EXIT_OK
	}
	print_probes_report(report)
	return EXIT_OK
}

@(private)
probe_scenario_volumes :: proc(
	path: string,
	allocator: mem.Allocator,
) -> ([]frame.Scene_Probe_Volume, string) {
	scenario, load_error := scenario_load(path, allocator)
	if load_error != "" {
		return nil, load_error
	}
	defer scenario_destroy(&scenario, allocator)
	extras: []frame.Scene_Probe_Volume
	for command in scenario.commands {
		#partial switch command.kind {
		case .Reset:
			frame.scene_probe_volumes_destroy(extras, allocator)
			extras = nil
		case .Scene:
			if command.scene.has_probe_volumes {
				frame.scene_probe_volumes_destroy(extras, allocator)
				extras = frame.scene_probe_volumes_clone(
					command.scene.scene.probe_volumes,
					allocator,
				)
			}
		}
	}
	return extras, ""
}

@(private)
parse_probe_point :: proc(text: string) -> ([3]f32, bool) {
	parts := strings.split(text, ",", context.temp_allocator)
	if len(parts) != 3 {
		return {}, false
	}
	point: [3]f32
	for part, index in parts {
		value, ok := strconv.parse_f32(strings.trim_space(part))
		if !ok {
			return {}, false
		}
		point[index] = value
	}
	return point, true
}

@(private)
print_probes_report :: proc(report: Probes_Report) {
	if report.scenario != "" {
		fmt.printf("scenario: %s\n", report.scenario)
	}
	fmt.printf("%d volumes, %d probes\n", report.count, report.probe_count)
	fmt.printf(
		"%-5s %-12s %-26s %-26s %-8s %-9s %-7s %s\n",
		"INDEX", "NAME", "MIN", "MAX", "SPACING", "COUNTS", "PROBES", "FIRST",
	)
	for volume in report.volumes {
		fmt.printf(
			"%-5d %-12s (%7.2f %7.2f %7.2f) (%7.2f %7.2f %7.2f) %-8.3f %-9s %-7d %d\n",
			volume.index,
			volume.name,
			volume.min.x,
			volume.min.y,
			volume.min.z,
			volume.max.x,
			volume.max.y,
			volume.max.z,
			volume.spacing,
			fmt.tprintf("%dx%dx%d", volume.counts.x, volume.counts.y, volume.counts.z),
			volume.probe_count,
			volume.first_probe,
		)
	}
	if len(report.points) > 0 {
		fmt.println("")
		for point in report.points {
			owner := "none"
			if point.volume >= 0 && point.volume < len(report.volumes) {
				owner = fmt.tprintf("%s (%d)", report.volumes[point.volume].name, point.volume)
			}
			fmt.printf(
				"point (%7.2f %7.2f %7.2f) -> %s\n",
				point.point.x,
				point.point.y,
				point.point.z,
				owner,
			)
		}
	}
	if coverage, has := report.coverage.?; has {
		fmt.println("")
		fmt.printf(
			"coverage: %d samples, %d outside (%.3f), %d shown\n",
			coverage.samples,
			coverage.outside,
			coverage.fraction,
			len(coverage.points),
		)
		for point in coverage.points {
			box := -1
			if value, has_box := point.box.?; has_box {
				box = value
			}
			fmt.printf(
				"  box %d point (%7.2f %7.2f %7.2f)\n",
				box,
				point.point.x,
				point.point.y,
				point.point.z,
			)
		}
	}
}


@(private)
print_probes_usage :: proc() {
	fmt.println("usage: harbagsa-agent probes [scenario] [--json] [--coverage] [--step M] [--point X,Y,Z]")
	fmt.println("")
	fmt.println("  --json          print {count, probe_count, volumes, points, coverage}")
	fmt.println("  --coverage      sample static box faces and report points no volume owns")
	fmt.println("  --step M        coverage sample step in metres (default 0.5)")
	fmt.println("  --point X,Y,Z   report the volume that owns a point; repeatable")
	fmt.println("  -h, --help      print this usage")
	fmt.println("")
	fmt.println("A scenario's scene 'probe_volumes' block adds its own interior volumes")
	fmt.println("after the room volume and before the arena strips. Without a scenario,")
	fmt.println("the production scene is printed.")
}
