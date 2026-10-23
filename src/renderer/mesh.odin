#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
}

#assert(size_of(Vertex) == 24)

// The unit cube has four vertices per face so every face has its own normal.
CUBE_VERTICES := [24]Vertex {
	{{-0.5, -0.5, 0.5}, {0, 0, 1}},
	{{0.5, -0.5, 0.5}, {0, 0, 1}},
	{{0.5, 0.5, 0.5}, {0, 0, 1}},
	{{-0.5, 0.5, 0.5}, {0, 0, 1}},
	{{0.5, -0.5, -0.5}, {0, 0, -1}},
	{{-0.5, -0.5, -0.5}, {0, 0, -1}},
	{{-0.5, 0.5, -0.5}, {0, 0, -1}},
	{{0.5, 0.5, -0.5}, {0, 0, -1}},
	{{0.5, -0.5, 0.5}, {1, 0, 0}},
	{{0.5, -0.5, -0.5}, {1, 0, 0}},
	{{0.5, 0.5, -0.5}, {1, 0, 0}},
	{{0.5, 0.5, 0.5}, {1, 0, 0}},
	{{-0.5, -0.5, -0.5}, {-1, 0, 0}},
	{{-0.5, -0.5, 0.5}, {-1, 0, 0}},
	{{-0.5, 0.5, 0.5}, {-1, 0, 0}},
	{{-0.5, 0.5, -0.5}, {-1, 0, 0}},
	{{-0.5, 0.5, 0.5}, {0, 1, 0}},
	{{0.5, 0.5, 0.5}, {0, 1, 0}},
	{{0.5, 0.5, -0.5}, {0, 1, 0}},
	{{-0.5, 0.5, -0.5}, {0, 1, 0}},
	{{-0.5, -0.5, -0.5}, {0, -1, 0}},
	{{0.5, -0.5, -0.5}, {0, -1, 0}},
	{{0.5, -0.5, 0.5}, {0, -1, 0}},
	{{-0.5, -0.5, 0.5}, {0, -1, 0}},
}

CUBE_INDICES := [36]u16 {
	0, 1, 2, 0, 2, 3,
	4, 5, 6, 4, 6, 7,
	8, 9, 10, 8, 10, 11,
	12, 13, 14, 12, 14, 15,
	16, 17, 18, 16, 18, 19,
	20, 21, 22, 20, 22, 23,
}

create_mesh :: proc(r: ^Renderer) -> bool {
	if !create_device_buffer(
		r,
		raw_data(CUBE_VERTICES[:]),
		vk.DeviceSize(size_of(CUBE_VERTICES)),
		{.VERTEX_BUFFER},
		&r.scene.vertex_buffer,
		&r.scene.vertex_memory,
	) {
		return false
	}
	if !create_device_buffer(
		r,
		raw_data(CUBE_INDICES[:]),
		vk.DeviceSize(size_of(CUBE_INDICES)),
		{.INDEX_BUFFER},
		&r.scene.index_buffer,
		&r.scene.index_memory,
	) {
		return false
	}
	r.scene.index_count = u32(len(CUBE_INDICES))
	return true
}
