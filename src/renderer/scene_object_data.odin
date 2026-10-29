#+vet explicit-allocators
package renderer

import "core:log"

import "src:bake"
import "src:geometry"

write_object_data :: proc(
	r: ^Renderer,
	boxes: []geometry.Box,
	slots: []bake.Box_Slot,
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
	if len(slots) != len(boxes) {
		log.errorf(
			"renderer: %d box slots do not match %d boxes",
			len(slots),
			len(boxes),
		)
		return false
	}

	if len(taa.prev_models) < len(boxes) {
		resize(&taa.prev_models, len(boxes))
	}

	for box, index in boxes {
		model := box_model_matrix(box)
		previous := model
		if index < taa.prev_model_count {
			previous = taa.prev_models[index]
		}
		slot, has_lightmap := bake_box_slot(r, slots[index])
		weight := f32(0.0)
		if has_lightmap && lightmap_enabled {
			weight = 1.0
		}
		data[index] = Object_Data {
			model           = model,
			prev_model      = previous,
			color           = {box.color.x, box.color.y, box.color.z, box.emissive},
			lightmap_slot   = slot,
			lightmap_weight = weight,
		}
		taa.prev_models[index] = model
	}
	taa.prev_model_count = len(boxes)
	taa.has_prev_models = true
	return true
}
