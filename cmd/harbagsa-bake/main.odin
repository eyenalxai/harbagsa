#+vet explicit-allocators
package main

import "core:fmt"
import "core:os"
import "core:strconv"

import "src:bake"
import "src:game"

DEFAULT_OUTPUT :: "build/bake/arena.hbake"

main :: proc() {
	os.exit(run(os.args[1:]))
}

run :: proc(args: []string) -> int {
	output := DEFAULT_OUTPUT
	spacing := f32(bake.PROBE_SPACING)
	threads := default_threads()

	index := 0
	for index < len(args) {
		argument := args[index]
		switch argument {
		case "--help", "-h":
			usage()
			return 0
		case "--out", "-o":
			if index + 1 >= len(args) {
				return argument_error("--out needs a path")
			}
			output = args[index + 1]
			index += 2
		case "--probe-spacing":
			if index + 1 >= len(args) {
				return argument_error("--probe-spacing needs 1 or 2")
			}
			value, value_ok := strconv.parse_f32(args[index + 1])
			if !value_ok ||
			   (value != f32(bake.PROBE_SPACING) && value != f32(bake.PROBE_SPACING_FALLBACK)) {
				return argument_error("--probe-spacing must be 1 or 2")
			}
			spacing = value
			index += 2
		case "--threads":
			if index + 1 >= len(args) {
				return argument_error("--threads needs a count")
			}
			value, value_ok := strconv.parse_int(args[index + 1])
			if !value_ok || value < 1 || value > bake.MAX_THREADS {
				return argument_error("--threads must be between 1 and 256")
			}
			threads = value
			index += 2
		case:
			fmt.eprintf("harbagsa-bake: unknown argument %q\n", argument)
			usage()
			return 2
		}
	}

	simulation := game.simulation_create(context.allocator)
	defer game.simulation_destroy(&simulation)
	if !game.simulation_is_valid(&simulation) {
		fmt.eprintln("harbagsa-bake: cannot create the simulation world")
		return 1
	}
	input: game.Bake_Input
	defer game.bake_input_destroy(&input)
	static := game.simulation_bake_input(&simulation, &input, context.allocator)

	quality := bake.DEFAULT_QUALITY
	quality.probe_spacing = spacing
	artifact, report, build_error := bake.build(
		static,
		{quality = quality, threads = threads},
		context.allocator,
	)
	if build_error != .None {
		fmt.eprintf("harbagsa-bake: %s\n", bake.build_error_name(build_error))
		return 1
	}
	defer delete(artifact, context.allocator)

	if write_error := bake.write_file(output, artifact); write_error != "" {
		fmt.eprintf("harbagsa-bake: %s\n", write_error)
		return 1
	}
	print_report(output, spacing, threads, report)
	return 0
}

@(private)
default_threads :: proc() -> int {
	threads, ok := bake.default_threads()
	if !ok {
		fmt.eprintln("harbagsa-bake: cannot read the CPU count; using one thread")
	}
	return threads
}

@(private)
usage :: proc() {
	fmt.println("usage: harbagsa-bake [--out PATH] [--probe-spacing 1|2] [--threads N]")
	fmt.println("  --out PATH          artifact path (default build/bake/arena.hbake)")
	fmt.println("  --probe-spacing M   1 m grid, or the 2 m fallback")
	fmt.println("  --threads N         worker count; the result does not depend on it")
}

@(private)
argument_error :: proc(message: string) -> int {
	fmt.eprintf("harbagsa-bake: %s\n", message)
	usage()
	return 2
}

@(private)
print_report :: proc(path: string, spacing: f32, threads: int, report: bake.Build_Report) {
	fmt.printf("harbagsa-bake: %s\n", path)
	fmt.printf("  key %016x  payload %016x\n", report.key, report.payload_hash)
	fmt.printf("  bake %d ms  threads %d\n", report.bake_ms, threads)
	fmt.printf(
		"  stages: bvh %d ms  lightmap %d ms  probes %d ms  encode %d ms\n",
		report.bvh_ms,
		report.lightmap_ms,
		report.probe_ms,
		report.encode_ms,
	)
	fmt.printf(
		"  static boxes %d  static lights %d  charts %d\n",
		report.boxes,
		report.lights,
		report.charts,
	)
	fmt.printf(
		"  atlas %dx%d (%d texels)  baked %d  invalid %d  dilated %d  %d bytes\n",
		report.atlas_size,
		report.atlas_size,
		report.atlas_size * report.atlas_size,
		report.valid_texels,
		report.invalid_texels,
		report.dilated_texels,
		report.atlas_bytes,
	)
	fmt.printf(
		"  rays: lightmap %d  probe %d  shadow %d\n",
		report.lightmap_rays,
		report.probe_rays,
		report.shadow_rays,
	)
	fmt.printf(
		"  probes %d at %.2f m  invalid %d  dilated %d  %d bytes\n",
		report.probes,
		spacing,
		report.invalid_probes,
		report.dilated_probes,
		report.probe_bytes,
	)
	fmt.printf("  artifact %d bytes\n", report.artifact_bytes)
}
