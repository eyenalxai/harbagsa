#+vet explicit-allocators
package harness

import "src:renderer"

View_State :: struct {
	hud:   bool `json:"hud"`,
	debug: bool `json:"debug"`,
	hint:  bool `json:"hint"`,
	perf:  bool `json:"perf"`,
}

Renderer_Config_State :: struct {
	device:           string `json:"device"`,
	shader_digest:    string `json:"shader_digest"`,
	taa:              bool   `json:"taa"`,
	frames_in_flight: int    `json:"frames_in_flight"`,
	jitter_samples:   int    `json:"jitter_samples"`,
	history_images:   int    `json:"history_images"`,
	max_samples:      int    `json:"max_samples"`,
	ao_samples:       int    `json:"ao_samples"`,
	ao_radius:        f32    `json:"ao_radius"`,
	ao_strength:      f32    `json:"ao_strength"`,
}

Setup_State :: struct {
	target:   string               `json:"target"`,
	width:    u32                  `json:"width"`,
	height:   u32                  `json:"height"`,
	revision:       string                `json:"revision"`,
	dirty:          bool                  `json:"dirty"`,
	renderer_debug: bool                  `json:"renderer_debug"`,
	view:           View_State            `json:"view"`,
	renderer:       Renderer_Config_State `json:"renderer"`,
}

setup_build :: proc(
	options: Common_Options,
	view: View,
	backend: Backend,
	renderer_debug := false,
) -> Setup_State {
	setup := Setup_State {
		target = "none",
		width = options.width,
		height = options.height,
		revision = HARNESS_REVISION,
		dirty = HARNESS_DIRTY,
		renderer_debug = renderer_debug || renderer.RENDERER_DEBUG_ENABLED,
		view = {hud = view.hud, debug = view.debug, hint = view.hint, perf = view.perf},
		renderer = {
			shader_digest = renderer.shader_digest(),
			frames_in_flight = 0,
			jitter_samples = renderer.TAA_JITTER_SAMPLES,
			history_images = renderer.TAA_HISTORY_IMAGES,
			max_samples = renderer.TAA_MAX_SAMPLES,
			ao_samples = renderer.AO_SAMPLES,
			ao_radius = renderer.AO_RADIUS,
			ao_strength = renderer.AO_STRENGTH,
		},
	}
	if !backend.ready || backend.setup == nil {
		return setup
	}
	report := backend.setup(backend.ctx)
	setup.target = report.target == .Swapchain ? "swapchain" : "offscreen"
	setup.width = report.width
	setup.height = report.height
	setup.renderer = {
		device = report.device,
		shader_digest = report.shader_digest,
		taa = report.taa,
		frames_in_flight = report.frames_in_flight,
		jitter_samples = report.jitter_samples,
		history_images = report.history_images,
		max_samples = report.max_samples,
		ao_samples = report.ao_samples,
		ao_radius = report.ao_radius,
		ao_strength = report.ao_strength,
	}
	return setup
}
