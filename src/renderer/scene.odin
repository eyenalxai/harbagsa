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

Scene :: struct {
	vertex_buffer: vk.Buffer,
	vertex_memory: vk.DeviceMemory,
	index_buffer:  vk.Buffer,
	index_memory:  vk.DeviceMemory,
	index_count:   u32,

	pipeline_layout:       vk.PipelineLayout,
	pipeline:              vk.Pipeline,
	pipeline_format:       vk.Format,
	descriptor_set_layout: vk.DescriptorSetLayout,
	descriptor_pool:       vk.DescriptorPool,
	descriptor_sets:       [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,

	camera_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	camera_memory:  [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	camera_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,
}

init_scene :: proc(r: ^Renderer) -> Error {
	if !create_camera_resources(r) {
		return .Create_Scene
	}
	if !create_mesh(r) {
		return .Create_Scene
	}
	if !create_pipeline(r) {
		return .Create_Pipeline
	}
	if !create_shadow_resources(r) {
		return .Create_Shadow
	}
	return .None
}

destroy_scene :: proc(r: ^Renderer) {
	if r.device == nil {
		return
	}

	destroy_shadow(r)
	destroy_pipeline_pair(r, &r.scene.pipeline, &r.scene.pipeline_layout)
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
	}

	destroy_buffer(r, &r.scene.vertex_buffer, &r.scene.vertex_memory)
	destroy_buffer(r, &r.scene.index_buffer, &r.scene.index_memory)
	r.scene.index_count = 0
}

update_camera :: proc(r: ^Renderer, camera: Camera, light_direction: [3]f32) -> bool {
	height := f32(r.target.config.height)
	if height <= 0 {
		log.error("renderer: cannot build a projection for a zero-height target")
		return false
	}
	aspect := f32(r.target.config.width) / height

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

	gamma: f32
	if !r.target.config.is_srgb {
		gamma = 1
	}
	fov_y := 2 * math.atan(math.tan(camera.fov_x * 0.5) / aspect)
	buffer^ = Camera_Uniform {
		view = view,
		projection = mat4_perspective(fov_y, aspect, CAMERA_NEAR, CAMERA_FAR),
		// The fragment shader normalizes the direction.
		light_direction = {light_direction.x, light_direction.y, light_direction.z, 0},
		ambient = {AMBIENT_COLOR.x, AMBIENT_COLOR.y, AMBIENT_COLOR.z, 0},
		gamma = {gamma, 0, 0, 0},
		light_view_projection = r.shadow.light_view_projection,
	}
	return true
}
