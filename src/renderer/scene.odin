#+vet explicit-allocators
package renderer

import "core:log"
import "core:math"

import vk "vendor:vulkan"

CAMERA_UP :: [3]f32{0, 1, 0}
CAMERA_NEAR :: 0.05
CAMERA_FAR :: 200.0

Camera :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
	fov_x:    f32,
}

// The renderer accepts any sun the scene names, but a zero or absurd angular
// diameter has no valid tangent and would break every shadow ray.
SUN_ANGULAR_DIAMETER_LIMIT :: 45.0 * math.PI / 180.0
// The scene has no ambient term, so the occlusion rays darken the direct light.
// Crates are 1 m and the tunnel clearances are 0.9 to 1.35 m, so a 1.5 m ray
// reaches the surfaces that should darken without reaching across the arena.
AO_RADIUS :: 1.5
AO_STRENGTH :: 0.5
AO_SAMPLES :: #config(AO_SAMPLES, 8) // The Makefile sets it and the shader reads the same value.

Scene :: struct {
	vertex_buffer: vk.Buffer,
	vertex_memory: vk.DeviceMemory,
	index_buffer:  vk.Buffer,
	index_memory:  vk.DeviceMemory,
	index_count:   u32,

	pipeline_layout:       vk.PipelineLayout,
	pipeline:              vk.Pipeline,
	depth_layout:          vk.PipelineLayout,
	depth_pipeline:        vk.Pipeline,
	sky_pipeline:          vk.Pipeline,
	sky_layout:            vk.PipelineLayout,
	descriptor_set_layout: vk.DescriptorSetLayout,
	descriptor_pool:       vk.DescriptorPool,
	descriptor_sets:       [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,

	camera_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	camera_memory:  [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	camera_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,

	object_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	object_memory:  [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	object_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,

	light_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	light_memory:  [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	light_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,

	cluster_counts_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	cluster_counts_memory:  [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	cluster_counts_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,

	cluster_indices_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	cluster_indices_memory:  [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	cluster_indices_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,

	cluster_pipeline: vk.Pipeline,
	cluster_layout:   vk.PipelineLayout,

	object_capacity: int,
	light_capacity:  int,
}

init_scene :: proc(r: ^Renderer) -> Error {
	if !create_probe_resources(r) {
		return .Create_Scene
	}
	if !create_scene_resources(r) {
		return .Create_Scene
	}
	if !create_mesh(r) {
		return .Create_Scene
	}
	if !create_pipeline(r) {
		return .Create_Pipeline
	}
	if !create_cluster_pipeline(r) {
		return .Create_Pipeline
	}
	if !create_probe_pipelines(r) {
		return .Create_Pipeline
	}
	if !create_sky_pipeline(r) {
		return .Create_Pipeline
	}
	if !create_acceleration_resources(r) {
		return .Create_Acceleration
	}
	return .None
}

destroy_scene :: proc(r: ^Renderer) {
	if r.device == nil {
		return
	}

	destroy_acceleration(r)
	destroy_pipeline_pair(r, &r.scene.depth_pipeline, &r.scene.depth_layout)
	destroy_pipeline_pair(r, &r.scene.pipeline, &r.scene.pipeline_layout)
	destroy_pipeline_pair(r, &r.scene.sky_pipeline, &r.scene.sky_layout)
	destroy_pipeline_pair(r, &r.scene.cluster_pipeline, &r.scene.cluster_layout)
	if r.scene.descriptor_pool != 0 {
		vk.DestroyDescriptorPool(r.device, r.scene.descriptor_pool, nil)
		r.scene.descriptor_pool = 0
	}
	if r.scene.descriptor_set_layout != 0 {
		vk.DestroyDescriptorSetLayout(r.device, r.scene.descriptor_set_layout, nil)
		r.scene.descriptor_set_layout = 0
	}

	destroy_scene_frame_buffers(r)
	destroy_buffer(r, &r.scene.vertex_buffer, &r.scene.vertex_memory)
	destroy_buffer(r, &r.scene.index_buffer, &r.scene.index_memory)
	r.scene.index_count = 0
}

update_camera :: proc(r: ^Renderer, input: Render_Input) -> bool {
	extent := vk.Extent2D{input.width, input.height}
	height := f32(extent.height)
	if height <= 0 {
		log.error("renderer: cannot build a projection for a zero-height target")
		return false
	}
	if !(input.sun_angular_diameter > 0 &&
	   input.sun_angular_diameter < SUN_ANGULAR_DIAMETER_LIMIT) {
		log.errorf(
			"renderer: sun angular diameter %v is out of range",
			input.sun_angular_diameter,
		)
		return false
	}
	aspect := f32(extent.width) / height

	buffer := cast(^Camera_Uniform)r.scene.camera_mapped[r.frame_index]
	if buffer == nil {
		log.error("renderer: camera uniform buffer is not mapped")
		return false
	}

	cos_pitch := math.cos(input.camera.pitch)
	forward := [3]f32{
		-math.sin(input.camera.yaw) * cos_pitch,
		math.sin(input.camera.pitch),
		-math.cos(input.camera.yaw) * cos_pitch,
	}
	target := [3]f32 {
		input.camera.position.x + forward.x,
		input.camera.position.y + forward.y,
		input.camera.position.z + forward.z,
	}
	view := mat4_look_at(input.camera.position, target, CAMERA_UP)
	projection := mat4_perspective(
		2 * math.atan(math.tan(input.camera.fov_x * 0.5) / aspect),
		aspect,
		CAMERA_NEAR,
		CAMERA_FAR,
	)
	view_projection := mat4_multiply(projection, view)

	previous := view_projection
	if r.taa.has_prev_view_projection {
		previous = r.taa.prev_view_projection
	}
	r.taa.prev_view_projection = view_projection
	r.taa.has_prev_view_projection = true

	buffer^ = Camera_Uniform {
		view = view,
		projection = projection,
		prev_view_projection = previous,
		light_direction = {
			input.light_direction.x,
			input.light_direction.y,
			input.light_direction.z,
			0,
		},
		// The sun sample pattern rotates only while TAA can average it.
		screen = {
			srgb_gamma(r),
			f32(extent.width),
			height,
			f32(input.shadow_phase),
		},
		sun = {
			math.tan(input.sun_angular_diameter * 0.5),
			CAMERA_FAR,
			f32(len(input.lights)),
			r.debug.active && !r.debug.light_shadows ? 0 : 1,
		},
		jitter = {input.jitter.x, input.jitter.y, 0, 0},
		occlusion = {
			input.ao_radius,
			input.ao_strength,
			input.ao ? 1.0 : 0.0,
			input.clip_height,
		},
		probe = {
			f32(r.probe.volume_count),
			f32(r.probe.probe_count),
			input.gi ? 1.0 : 0.0,
			0,
		},
	}
	return true
}

// Jitter advances once per recorded frame. The digest, the uniform, and the
// report all read the value this call stores in the input.
taa_frame_jitter :: proc(r: ^Renderer, extent: vk.Extent2D) -> [2]f32 {
	jitter: [2]f32
	jitter_enabled := r.taa.enabled && !(r.debug.active && !r.debug.jitter)
	if jitter_enabled {
		r.taa.applied_jitter_index = r.taa.jitter_index
		jitter = taa_jitter(r.taa.jitter_index, extent)
		r.taa.jitter_index = (r.taa.jitter_index + 1) % TAA_JITTER_SAMPLES
	} else {
		r.taa.applied_jitter_index = 0
	}
	return jitter
}
