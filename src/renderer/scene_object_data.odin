#+vet explicit-allocators
package renderer

import "core:log"

import "src:bake"
import "src:geometry"

write_object_data :: proc(
	r: ^Renderer,
	boxes: []geometry.Box,
	slots: []bake.Box_Slot,
	lightmap_enabled, probe_enabled: bool,
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

	probe_missing := 0
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
		probe_weight := f32(0.0)
		if r.bake.loaded && probe_enabled && !slots[index].has_slot {
			probe_weight = 1.0
			if probe_outside_volume(r.bake.data.header, box.center) {
				probe_missing += 1
			}
		}
		data[index] = Object_Data {
			model           = model,
			prev_model      = previous,
			color           = {box.color.x, box.color.y, box.color.z, box.emissive},
			lightmap_slot   = slot,
			lightmap_weight = weight,
			probe_weight    = probe_weight,
		}
		taa.prev_models[index] = model
	}
	r.bake.probe_missing = probe_missing
	taa.prev_model_count = len(boxes)
	taa.has_prev_models = true
	return true
}

// The shader returns zero outside the volume. The arena is closed, so a
// dynamic object outside it is a bug; expose it instead of letting it read as
// an unlit surface.
@(private)
probe_outside_volume :: proc(header: bake.Header, center: [3]f32) -> bool {
	high := [3]f32 {
		header.probe_min.x + f32(header.probe_counts.x) * header.probe_spacing,
		header.probe_min.y + f32(header.probe_counts.y) * header.probe_spacing,
		header.probe_min.z + f32(header.probe_counts.z) * header.probe_spacing,
	}
	for axis in 0 ..< 3 {
		if center[axis] < header.probe_min[axis] || center[axis] > high[axis] {
			return true
		}
	}
	return false
}
