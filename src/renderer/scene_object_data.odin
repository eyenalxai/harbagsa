#+vet explicit-allocators
package renderer

import "core:log"

import "src:bake"
import "src:geometry"

write_object_data :: proc(
	r: ^Renderer,
	boxes: []geometry.Box,
	keys: []u64,
	lightmap_enabled: bool,
) -> bool {
	taa := &r.taa
	data := cast([^]Object_Data)r.scene.object_mapped[r.frame_index]
	if data == nil {
		log.error("renderer: object storage buffer is not mapped")
		return false
	}
	if len(boxes) > r.scene.object_capacity {
		log.errorf(
			"renderer: %d boxes exceed the %d-slot object buffer",
			len(boxes),
			r.scene.object_capacity,
		)
		return false
	}
	if len(keys) != len(boxes) {
		log.errorf("renderer: %d box keys do not match %d boxes", len(keys), len(boxes))
		return false
	}

	if len(taa.prev_models) < len(boxes) {
		resize(&taa.prev_models, len(boxes))
	}

	r.bake.mapped_boxes = 0
	r.bake.unmapped_boxes = 0
	for box, index in boxes {
		model := box_model_matrix(box)
		previous := model
		if index < taa.prev_model_count {
			previous = taa.prev_models[index]
		}
		slot := INVALID_LIGHTMAP_SLOT
		if lightmap_enabled && keys[index] != bake.NO_BOX_KEY {
			if found, ok := bake_slot_for(r, keys[index]); ok {
				slot = found
				r.bake.mapped_boxes += 1
			} else {
				r.bake.unmapped_boxes += 1
			}
		}
		data[index] = Object_Data {
			model = model,
			prev_model = previous,
			color = {box.color.x, box.color.y, box.color.z, box.emissive},
			lightmap = {slot, 0, 0, 0},
		}
		taa.prev_models[index] = model
	}
	taa.prev_model_count = len(boxes)
	taa.has_prev_models = true
	return true
}
