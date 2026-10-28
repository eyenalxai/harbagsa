#+vet explicit-allocators
#+vet !unused-procedures // the harness waits on the atlas before a capture
package renderer

import "core:log"
import "core:sync"

import vk "vendor:vulkan"

TEXT_ATLAS_BINDING :: 0

// The atlas changes only when the weight or the UI density does, so one sampler
// and one descriptor set outlive the texture they read.
init_text_atlas_resources :: proc(r: ^Renderer) -> bool {
	o := &r.overlay
	if !text_atlas_rebuild(r) {
		return false
	}
	o.atlas_applied_weight = BASE_WEIGHT

	if !create_clamp_sampler(r, &o.atlas_sampler) {
		return false
	}

	bindings := [1]vk.DescriptorSetLayoutBinding {
		{
			binding = TEXT_ATLAS_BINDING,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
	}
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings    = &bindings[0],
	}
	if !check(
		vk.CreateDescriptorSetLayout(r.device, &layout_info, nil, &o.atlas_layout),
		"vkCreateDescriptorSetLayout",
	) {
		return false
	}

	pool_size := vk.DescriptorPoolSize {
		type            = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = 1,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	if !check(vk.CreateDescriptorPool(r.device, &pool_info, nil, &o.atlas_pool), "vkCreateDescriptorPool") {
		return false
	}

	allocate := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = o.atlas_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &o.atlas_layout,
	}
	if !check(vk.AllocateDescriptorSets(r.device, &allocate, &o.atlas_set), "vkAllocateDescriptorSets") {
		return false
	}
	text_atlas_bind(r)
	return true
}

// Repacks the atlas for the overlay's current theme and points the descriptor at
// the new texture. Startup has nothing in flight, so it does not wait.
text_atlas_rebuild :: proc(r: ^Renderer) -> bool {
	o := &r.overlay
	set := text_theme_layer_set(o.theme)
	atlas, built := text_atlas_build(r.allocator, &set)
	if !built {
		return false
	}
	text_atlas_destroy(&o.atlas)
	o.atlas = atlas

	destroy_image(r, &o.atlas_image)
	image, uploaded := upload_texture(r, atlas.width, atlas.height, .R8_UNORM, atlas.pixels)
	if !uploaded {
		return false
	}
	o.atlas_image = image
	if o.atlas_set != 0 {
		text_atlas_bind(r)
	}
	return true
}

// Applies a finished atlas. Returns false only on a fatal device failure.
text_atlas_apply :: proc(r: ^Renderer) -> bool {
	o := &r.overlay
	worker := &o.atlas_worker
	sync.lock(&worker.mutex)
	if !worker.result_ready {
		sync.unlock(&worker.mutex)
		return true
	}
	result := worker.result
	weight := worker.result_weight
	worker.result = {}
	worker.result_ready = false
	sync.unlock(&worker.mutex)

	if result.shaper.buffer == nil {
		shaper, shaper_ok := text_shaper_init()
		if !shaper_ok {
			text_atlas_destroy(&result)
			text_atlas_mark_failed(worker)
			return true
		}
		result.shaper = shaper
	}

	if !check(vk.DeviceWaitIdle(r.device), "vkDeviceWaitIdle") {
		text_atlas_destroy(&result)
		return false
	}
	image, uploaded := upload_texture(r, result.width, result.height, .R8_UNORM, result.pixels)
	if !uploaded {
		text_atlas_destroy(&result)
		text_atlas_mark_failed(worker)
		return true
	}

	old_image := o.atlas_image
	// The caps are cumulative across rebuilds, so the new atlas inherits them
	// before the old one is destroyed.
	result.caps = o.atlas.caps
	text_atlas_destroy(&o.atlas)
	o.atlas = result
	o.atlas_applied_weight = weight
	o.atlas_image = image
	if o.atlas_set != 0 {
		text_atlas_bind(r)
	}
	destroy_image(r, &old_image)
	log.debugf("text atlas: applied weight %d", int(weight))
	return true
}

@(private)
text_atlas_mark_failed :: proc(worker: ^Text_Atlas_Worker) {
	sync.lock(&worker.mutex)
	worker.failed = true
	sync.unlock(&worker.mutex)
}

text_atlas_applied_weight :: proc(r: ^Renderer) -> f32 {
	return r.overlay.atlas_applied_weight
}

text_atlas_sync :: proc(r: ^Renderer, requested_weight: f32) -> bool {
	o := &r.overlay
	if o.atlas_worker.thread == nil && !text_atlas_worker_start(o) {
		return false
	}
	if !text_atlas_apply(r) {
		return false
	}
	requested := ui_theme_init(r.target.config.height, requested_weight)
	requested_set := text_theme_layer_set(requested)
	worker := &o.atlas_worker
	if text_atlas_covers(&o.atlas, requested_set) {
		sync.lock(&worker.mutex)
		// A request that the active atlas already satisfies must not be
		// overwritten by an older build that is still in flight.
		worker.job_pending = false
		worker.request_generation += 1
		worker.job_generation = 0
		worker.failed = false
		sync.unlock(&worker.mutex)
		return true
	}

	sync.lock(&worker.mutex)
	if worker.job_generation == 0 || !text_layer_set_equal(worker.job, requested_set) {
		worker.request_generation += 1
		worker.job = requested_set
		worker.job_weight = requested_weight
		worker.job_generation = worker.request_generation
		worker.job_pending = true
		worker.failed = false
		sync.cond_signal(&worker.job_cond)
	}
	sync.unlock(&worker.mutex)
	return true
}

// Blocks until the pending request has been built and applied. Captures call
// this so the image and the text theme agree.
text_atlas_wait :: proc(r: ^Renderer) -> bool {
	o := &r.overlay
	worker := &o.atlas_worker
	if worker.thread == nil {
		return true
	}
	for {
		if !text_atlas_apply(r) {
			return false
		}
		sync.lock(&worker.mutex)
		if !worker.job_pending && !worker.busy && !worker.result_ready {
			failed := worker.failed
			sync.unlock(&worker.mutex)
			return !failed
		}
		if worker.result_ready {
			sync.unlock(&worker.mutex)
			continue
		}
		sync.cond_wait(&worker.done_cond, &worker.mutex)
		sync.unlock(&worker.mutex)
	}
}

@(private)
text_atlas_bind :: proc(r: ^Renderer) {
	o := &r.overlay
	descriptor := vk.DescriptorImageInfo {
		sampler     = o.atlas_sampler,
		imageView   = o.atlas_image.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}
	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = o.atlas_set,
		dstBinding      = TEXT_ATLAS_BINDING,
		descriptorCount = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		pImageInfo      = &descriptor,
	}
	vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
}

destroy_text_atlas_resources :: proc(r: ^Renderer) {
	overlay := &r.overlay
	text_atlas_worker_stop(overlay)
	if r.device != nil {
		if overlay.atlas_pool != 0 {
			vk.DestroyDescriptorPool(r.device, overlay.atlas_pool, nil)
			overlay.atlas_pool = 0
			overlay.atlas_set = 0
		}
		if overlay.atlas_layout != 0 {
			vk.DestroyDescriptorSetLayout(r.device, overlay.atlas_layout, nil)
			overlay.atlas_layout = 0
		}
		if overlay.atlas_sampler != 0 {
			vk.DestroySampler(r.device, overlay.atlas_sampler, nil)
			overlay.atlas_sampler = 0
		}
		destroy_image(r, &overlay.atlas_image)
	}
	text_atlas_destroy(&overlay.atlas)
}
