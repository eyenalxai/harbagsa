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

AMBIENT_COLOR :: [3]f32{0.24, 0.25, 0.28}
// The renderer accepts any sun the scene names, but a zero or absurd angular
// diameter has no valid tangent and would break every shadow ray.
SUN_ANGULAR_DIAMETER_LIMIT :: 45.0 * math.PI / 180.0
// Crates are 1 m and the tunnel clearances are 0.9 to 1.35 m, so a 1.5 m ray
// reaches the surfaces that should darken without reaching across the arena.
AO_RADIUS :: 1.5
AO_STRENGTH :: 1.0
AO_SAMPLES :: 8 // Must match AO_SAMPLES in box.frag. The setup report reads it.

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
}

init_scene :: proc(r: ^Renderer) -> Error {
	if !create_scene_resources(r) {
		return .Create_Scene
	}
	if !create_mesh(r) {
		return .Create_Scene
	}
	if !create_pipeline(r) {
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
	if r.scene.descriptor_pool != 0 {
		vk.DestroyDescriptorPool(r.device, r.scene.descriptor_pool, nil)
		r.scene.descriptor_pool = 0
	}
	if r.scene.descriptor_set_layout != 0 {
		vk.DestroyDescriptorSetLayout(r.device, r.scene.descriptor_set_layout, nil)
		r.scene.descriptor_set_layout = 0
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if r.scene.camera_mapped[i] != nil {
			vk.UnmapMemory(r.device, r.scene.camera_memory[i])
			r.scene.camera_mapped[i] = nil
		}
		destroy_buffer(r, &r.scene.camera_buffers[i], &r.scene.camera_memory[i])

		if r.scene.object_mapped[i] != nil {
			vk.UnmapMemory(r.device, r.scene.object_memory[i])
			r.scene.object_mapped[i] = nil
		}
		destroy_buffer(r, &r.scene.object_buffers[i], &r.scene.object_memory[i])
	}

	destroy_buffer(r, &r.scene.vertex_buffer, &r.scene.vertex_memory)
	destroy_buffer(r, &r.scene.index_buffer, &r.scene.index_memory)
	r.scene.index_count = 0
}

update_camera :: proc(
	r: ^Renderer,
	camera: Camera,
	light_direction: [3]f32,
	sun_angular_diameter: f32,
) -> bool {
	extent := vk.Extent2D{r.target.config.width, r.target.config.height}
	height := f32(extent.height)
	if height <= 0 {
		log.error("renderer: cannot build a projection for a zero-height target")
		return false
	}
	if !(sun_angular_diameter > 0 && sun_angular_diameter < SUN_ANGULAR_DIAMETER_LIMIT) {
		log.errorf("renderer: sun angular diameter %v is out of range", sun_angular_diameter)
		return false
	}
	aspect := f32(extent.width) / height

	buffer := cast(^Camera_Uniform)r.scene.camera_mapped[r.frame_index]
	if buffer == nil {
		log.error("renderer: camera uniform buffer is not mapped")
		return false
	}

	cos_pitch := math.cos(camera.pitch)
	forward := [3]f32{
		-math.sin(camera.yaw) * cos_pitch,
		math.sin(camera.pitch),
		-math.cos(camera.yaw) * cos_pitch,
	}
	target := [3]f32 {
		camera.position.x + forward.x,
		camera.position.y + forward.y,
		camera.position.z + forward.z,
	}
	view := mat4_look_at(camera.position, target, CAMERA_UP)
	projection := mat4_perspective(
		2 * math.atan(math.tan(camera.fov_x * 0.5) / aspect),
		aspect,
		CAMERA_NEAR,
		CAMERA_FAR,
	)
	view_projection := mat4_multiply(projection, view)

	taa_note_camera(r, camera)

	previous := view_projection
	if r.taa.has_prev_view_projection {
		previous = r.taa.prev_view_projection
	}
	r.taa.prev_view_projection = view_projection
	r.taa.has_prev_view_projection = true

	jitter: [2]f32
	jitter_enabled := r.taa.enabled && !(r.taa.debug.active && !r.taa.debug.jitter)
	if jitter_enabled {
		r.taa.applied_jitter_index = r.taa.jitter_index
		jitter = taa_jitter(r.taa.jitter_index, extent)
		r.taa.jitter_index = (r.taa.jitter_index + 1) % TAA_JITTER_SAMPLES
	} else {
		r.taa.applied_jitter_index = 0
	}
	r.taa.current_jitter = jitter
	r.taa.shadow_phase = taa_shadow_phase(r)
	debug := renderer_debug(r)

	buffer^ = Camera_Uniform {
		view = view,
		projection = projection,
		prev_view_projection = previous,
		light_direction = {light_direction.x, light_direction.y, light_direction.z, 0},
		ambient = {AMBIENT_COLOR.x, AMBIENT_COLOR.y, AMBIENT_COLOR.z, 0},
		// The sun sample pattern rotates only while TAA can average it.
		screen = {srgb_gamma(r), f32(extent.width), height, f32(r.taa.shadow_phase)},
		sun = {math.tan(sun_angular_diameter * 0.5), CAMERA_FAR, 0, 0},
		jitter = {jitter.x, jitter.y, 0, 0},
		lighting = {
			AO_RADIUS,
			AO_STRENGTH,
			debug.ao ? 1.0 : 0.0,
			debug.sky ? 1.0 : 0.0,
		},
	}
	return true
}
