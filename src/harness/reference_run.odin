#+vet explicit-allocators
package harness

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

import "src:frame"
import "src:game"
import "src:reference"
import "src:renderer"

Reference_Captures :: struct {
	gi:     string `json:"gi"`,
	direct: string `json:"direct"`,
}

Reference_Camera :: struct {
	position:  [3]f32 `json:"position"`,
	yaw_deg:   f32    `json:"yaw_deg"`,
	pitch_deg: f32    `json:"pitch_deg"`,
	fov_deg:   f32    `json:"fov_deg"`,
}

Reference_Scene :: struct {
	width:                    u32              `json:"width"`,
	height:                   u32              `json:"height"`,
	boxes:                    int              `json:"boxes"`,
	lights:                   int              `json:"lights"`,
	sun_direction:            [3]f32           `json:"sun_direction"`,
	sun_angular_diameter_deg: f32              `json:"sun_angular_diameter_deg"`,
	camera:                   Reference_Camera `json:"camera"`,
}

Reference_Image :: struct {
	path:   string `json:"path"`,
	width:  u32    `json:"width"`,
	height: u32    `json:"height"`,
}

Reference_Report :: struct {
	name:       string              `json:"name"`,
	captures:   Reference_Captures  `json:"captures"`,
	scene:      Reference_Scene     `json:"scene"`,
	estimator:  reference.Settings  `json:"estimator"`,
	metrics:    reference.Metrics   `json:"metrics"`,
	tolerance:  reference.Tolerance `json:"tolerance"`,
	image:      Reference_Image     `json:"image"`,
	ok:         bool                `json:"ok"`,
	elapsed_ms: f64                 `json:"elapsed_ms"`,
}

@(private)
execute_reference :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	spec := command.reference
	if session.render.backend != nil {
		session_refresh_renderer(session)
	}
	if gate_error := reference_debug_gate(session); gate_error != "" {
		return gate_error
	}
	gi, gi_error := reference_capture(session, spec.gi)
	if gi_error != "" {
		return gi_error
	}
	direct, direct_error := reference_capture(session, spec.direct)
	if direct_error != "" {
		return direct_error
	}
	if gi.width != direct.width || gi.height != direct.height {
		return format_error("the reference captures have different extents")
	}
	gi_values, gi_read_error := reference_read(gi, session.allocator)
	if gi_read_error != "" {
		return gi_read_error
	}
	defer delete(gi_values, session.allocator)
	direct_values, direct_read_error := reference_read(direct, session.allocator)
	if direct_read_error != "" {
		return direct_read_error
	}
	defer delete(direct_values, session.allocator)

	scene_input := reference_scene_input(session)
	scene := reference.Scene {
		boxes = scene_input.boxes,
		sun_direction = linalg.vector_normalize0(-scene_input.light_direction),
		sun_angle = scene_input.sun_angular_diameter,
		camera = {
			position = scene_input.camera.position,
			yaw = scene_input.camera.yaw,
			pitch = scene_input.camera.pitch,
			fov_x = scene_input.camera.fov_x,
		},
	}
	lights := make([]reference.Light, len(scene_input.lights), session.allocator)
	defer delete(lights, session.allocator)
	for light, index in scene_input.lights {
		lights[index] = {
			position = light.position,
			color = light.color,
			intensity = light.intensity,
			range = light.range,
		}
	}
	scene.lights = lights

	started := time.tick_now()
	grid := reference.estimate(scene, spec.settings, gi.width, gi.height, session.allocator)
	defer reference.Grid_Destroy(&grid, session.allocator)
	comparison := reference.compare(
		gi_values,
		direct_values,
		gi.width,
		gi.height,
		grid,
		session.allocator,
	)
	defer reference.Comparison_Destroy(&comparison, session.allocator)
	elapsed_ms := f64(time.tick_since(started)) / f64(time.Millisecond)

	report := reference_report_new(session, spec, scene, grid, gi.width, gi.height, comparison, elapsed_ms)
	report.ok = reference.metrics_within(comparison.metrics, spec.tolerance)
	if write_error := reference_write(session, spec, grid, comparison, report); write_error != "" {
		reference_report_destroy(&report, session.allocator)
		return write_error
	}
	append(&session.references, report)
	reply.reference = &session.references[len(session.references) - 1]
	if !report.ok {
		// A gate failure joins the run's failures instead of ending the
		// command list, so one run compares every scene it declares.
		message := reference_gate_message(report)
		session_failure(session, message)
		delete(message, session.allocator)
	}
	return ""
}

@(private)
reference_debug_gate :: proc(session: ^Session) -> string {
	debug := session.render.debug
	if !debug.active {
		return format_error(
			"%s",
			"the reference needs renderer debug overrides: set taa, jitter, and ao off",
		)
	}
	if debug.taa || debug.jitter {
		return format_error("%s", "the reference needs taa and jitter off")
	}
	if debug.ao {
		return format_error("%s", "the reference has no ambient occlusion; set ao off")
	}
	if !debug.sky {
		return format_error("%s", "the reference needs the sky pass on")
	}
	if !debug.light_shadows {
		return format_error("%s", "the reference needs the point-light shadows on")
	}
	if debug.synthetic_lights > 0 {
		return format_error("%s", "the reference cannot use synthetic lights")
	}
	if session.view.hud || session.hud.menu.open {
		return format_error("%s", "the reference needs the HUD and the menu closed")
	}
	return ""
}

@(private)
reference_capture :: proc(session: ^Session, name: string) -> (^Capture_Result, string) {
	for index in 0 ..< len(session.capture.captures) {
		capture := &session.capture.captures[index]
		if capture.name == name {
			if capture.target != "scene_color" || capture.format != "float" {
				return nil, fmt.aprintf(
					"capture %q must be a scene_color float capture",
					name,
					allocator = context.allocator,
				)
			}
			return capture, ""
		}
	}
	return nil, fmt.aprintf("no capture named %q", name, allocator = context.allocator)
}

@(private)
reference_read :: proc(capture: ^Capture_Result, allocator: mem.Allocator) -> ([]f32, string) {
	required := int(capture.width) * int(capture.height) * 4
	if required <= 0 || capture.path == "" {
		return nil, fmt.aprintf(
			"capture %q has no pixel file",
			capture.name,
			allocator = context.allocator,
		)
	}
	data, read_error := os.read_entire_file(capture.path, allocator)
	if read_error != nil {
		return nil, fmt.aprintf(
			"cannot read %s: %v",
			capture.path,
			read_error,
			allocator = context.allocator,
		)
	}
	defer delete(data, allocator)
	if len(data) != required * 4 {
		return nil, fmt.aprintf(
			"%s holds %d bytes, expected %d",
			capture.path,
			len(data),
			required * 4,
			allocator = context.allocator,
		)
	}
	values := make([]f32, required, allocator)
	mem.copy(raw_data(values), raw_data(data), len(data))
	return values, ""
}

@(private)
reference_scene_input :: proc(session: ^Session) -> renderer.Render_Input {
	options := frame.Options {
		alpha = session.alpha,
		delta_seconds = game.SIMULATION_STEP,
		debug_view = session.view.debug,
		captured = !session.view.hint,
		hud = false,
		perf = false,
	}
	camera_override: ^renderer.Camera
	if session.has_camera_override {
		camera_override = &session.camera_override
	}
	return frame.build(&session.sim, &session.debug, options, camera_override, &session.hud, session.scratch)
}

@(private)
reference_report_new :: proc(
	session: ^Session,
	spec: Reference_Command,
	scene: reference.Scene,
	grid: reference.Grid,
	width, height: u32,
	comparison: reference.Comparison,
	elapsed_ms: f64,
) -> Reference_Report {
	allocator := session.allocator
	return {
		name = strings.clone(spec.name, allocator),
		captures = {
			gi = strings.clone(spec.gi, allocator),
			direct = strings.clone(spec.direct, allocator),
		},
		scene = {
			width = width,
			height = height,
			boxes = len(scene.boxes),
			lights = len(scene.lights),
			sun_direction = scene.sun_direction,
			sun_angular_diameter_deg = f32(math.to_degrees(scene.sun_angle)),
			camera = {
				position = scene.camera.position,
				yaw_deg = f32(math.to_degrees(scene.camera.yaw)),
				pitch_deg = f32(math.to_degrees(scene.camera.pitch)),
				fov_deg = f32(math.to_degrees(scene.camera.fov_x)),
			},
		},
		estimator = spec.settings,
		metrics = comparison.metrics,
		tolerance = spec.tolerance,
		image = {
			path = fmt.aprintf("frames/%s-reference.png", spec.name, allocator = allocator),
			width = u32(grid.width),
			height = u32(grid.height),
		},
		elapsed_ms = elapsed_ms,
	}
}

@(private)
reference_write :: proc(
	session: ^Session,
	spec: Reference_Command,
	grid: reference.Grid,
	comparison: reference.Comparison,
	report: Reference_Report,
) -> string {
	frames_dir := join_path({session.output_dir, "frames"}, session.allocator)
	defer delete(frames_dir, session.allocator)
	pixels := reference.grid_pixels(grid, session.allocator)
	defer delete(pixels, session.allocator)
	image_name := fmt.aprintf("%s-reference", spec.name, allocator = context.temp_allocator)
	written, png_error := write_png_file(
		frames_dir,
		image_name,
		u32(grid.width),
		u32(grid.height),
		pixels,
		session.allocator,
	)
	if png_error != "" {
		return png_error
	}
	delete(written, session.allocator)

	csv := reference_csv(comparison, session.allocator)
	defer delete(csv, session.allocator)
	csv_name := fmt.aprintf("%s-reference.csv", spec.name, allocator = context.temp_allocator)
	csv_path := join_path({session.output_dir, csv_name}, session.allocator)
	defer delete(csv_path, session.allocator)
	if write_error := os.write_entire_file(csv_path, csv); write_error != nil {
		return fmt.aprintf(
			"cannot write %s: %v",
			csv_path,
			write_error,
			allocator = context.allocator,
		)
	}

	json_name := fmt.aprintf("%s-reference.json", spec.name, allocator = context.temp_allocator)
	json_path := join_path({session.output_dir, json_name}, session.allocator)
	defer delete(json_path, session.allocator)
	return write_json_file(json_path, report)
}

@(private)
reference_csv :: proc(comparison: reference.Comparison, allocator: mem.Allocator) -> []u8 {
	builder := strings.builder_make(allocator)
	strings.write_string(
		&builder,
		"x,y,box,reference_r,reference_g,reference_b,gpu_r,gpu_g,gpu_b,ratio,error\n",
	)
	for point in comparison.points {
		fmt.sbprintf(
			&builder,
			"%d,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.5f,%.5f\n",
			point.x,
			point.y,
			point.box,
			point.reference.x,
			point.reference.y,
			point.reference.z,
			point.gpu.x,
			point.gpu.y,
			point.gpu.z,
			point.ratio,
			point.error,
		)
	}
	return transmute([]u8)strings.to_string(builder)
}

@(private)
reference_gate_message :: proc(report: Reference_Report) -> string {
	metrics := report.metrics
	tolerance := report.tolerance
	return fmt.aprintf(
		"reference %s is outside tolerance: ratio %.3f in [%.2f, %.2f], median error %.3f <= %.2f, colour spread %.3f <= %.2f, zero %.1f%% <= %.1f%%",
		report.name,
		metrics.ratio,
		tolerance.ratio_min,
		tolerance.ratio_max,
		metrics.error,
		tolerance.error_max,
		metrics.colour_spread,
		tolerance.colour_max,
		metrics.zero_fraction * 100.0,
		tolerance.zero_fraction_max * 100.0,
		allocator = context.allocator,
	)
}

@(private)
reference_report_destroy :: proc(report: ^Reference_Report, allocator: mem.Allocator) {
	delete(report.name, allocator)
	delete(report.captures.gi, allocator)
	delete(report.captures.direct, allocator)
	delete(report.image.path, allocator)
	report^ = {}
}
