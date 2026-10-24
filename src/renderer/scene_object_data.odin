#+vet explicit-allocators
package renderer

import "core:log"

import "src:geometry"

write_object_data :: proc(r: ^Renderer, boxes: []geometry.Box) -> bool {
	taa := &r.taa
	data := cast([^]Object_Data)r.scene.object_mapped[r.frame_index]
	if data == nil {
		log.error("renderer: object storage buffer is not mapped")
		return false
	}

	models: [MAX_SCENE_BOXES]Mat4
	for box, index in boxes {
		models[index] = box_model_matrix(box)
		previous := models[index]
		if index < taa.prev_model_count {
			previous = taa.prev_models[index]
		}
		data[index] = Object_Data {
			model = models[index],
			prev_model = previous,
			color = {box.color.x, box.color.y, box.color.z, box.emissive},
		}
	}
	for index in 0 ..< len(boxes) {
		taa.prev_models[index] = models[index]
	}
	taa.prev_model_count = len(boxes)
	taa.has_prev_models = true
	return true
}
