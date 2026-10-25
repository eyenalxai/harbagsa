#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"

Boxes_Report :: struct {
	count: int                `json:"count"`,
	boxes: []Static_Box_State `json:"boxes"`,
}

cli_boxes :: proc(args: []string) -> int {
	json_output := false
	for argument in args {
		switch argument {
		case "--help", "-h":
			print_boxes_usage()
			return EXIT_OK
		case "--json":
			json_output = true
		case:
			fmt.eprintf("harbagsa-agent boxes: unknown option %q\n", argument)
			print_boxes_usage()
			return EXIT_SCENARIO
		}
	}

	session, session_error := session_create(context.allocator)
	if session_error != "" {
		fmt.eprintf("harbagsa-agent boxes: %s\n", session_error)
		delete(session_error, context.allocator)
		return EXIT_RENDER
	}
	defer session_destroy(&session)

	state := state_build_sections(
		&session.sim,
		0,
		&session.hud,
		&session.debug,
		{},
		{},
		"",
		{},
		{.Static_Boxes},
		context.allocator,
	)
	defer state_destroy(&state, context.allocator)

	report := Boxes_Report{count = len(state.static_boxes), boxes = state.static_boxes}
	if json_output {
		data, marshal_error := json.marshal(report, {}, context.allocator)
		if marshal_error != nil {
			fmt.eprintln("harbagsa-agent boxes: cannot encode the box list")
			return EXIT_RENDER
		}
		defer delete(data, context.allocator)
		fmt.println(string(data))
		return EXIT_OK
	}

	fmt.printf("%-5s %-18s %-18s %-16s %-8s %s\n", "INDEX", "CENTER", "HALF EXTENTS", "COLOR", "EMISSIVE", "VISUAL")
	for box, index in state.static_boxes {
		fmt.printf(
			"%-5d (%7.2f %7.2f %7.2f) (%5.2f %5.2f %5.2f) (%4.2f %4.2f %4.2f) %-8.2f %v\n",
			index,
			box.center.x,
			box.center.y,
			box.center.z,
			box.half_extents.x,
			box.half_extents.y,
			box.half_extents.z,
			box.color.r,
			box.color.g,
			box.color.b,
			box.emissive,
			box.visual_only,
		)
	}
	return EXIT_OK
}

@(private)
print_boxes_usage :: proc() {
	fmt.println("usage: harbagsa-agent boxes [--json]")
	fmt.println("")
	fmt.println("  --json   print {count, boxes} with every static arena box")
	fmt.println("  -h, --help  print this usage")
	fmt.println("")
	fmt.println("Every centre and half extent is in metres. A visual-only box does not")
	fmt.println("collide; an emissive box is a lamp.")
}
