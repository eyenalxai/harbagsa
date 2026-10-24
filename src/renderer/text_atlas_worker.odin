#+vet explicit-allocators
package renderer

import "core:log"
import "core:mem"
import "core:sync"
import "core:thread"

// One worker builds atlas replacements. Requests coalesce to the newest layer
// set; the main thread applies a finished atlas when it reaches the front of a
// frame. The active atlas keeps drawing until then.
Text_Atlas_Worker :: struct {
	mutex:              sync.Mutex,
	job_cond:           sync.Cond,
	done_cond:          sync.Cond,
	thread:             ^thread.Thread,
	quit:               bool,
	busy:               bool,
	job:                Text_Layer_Set,
	job_weight:         f32,
	job_generation:     u64,
	job_pending:        bool,
	request_generation: u64,
	result:             Text_Atlas,
	result_weight:      f32,
	result_ready:       bool,
	failed:             bool,
}

@(private)
text_atlas_worker_start :: proc(o: ^Overlay) -> bool {
	worker := &o.atlas_worker
	worker.thread = thread.create(text_atlas_worker_main, .Normal, "text atlas")
	if worker.thread == nil {
		log.error("text atlas: could not start the worker")
		return false
	}
	worker.thread.data = o
	thread.start(worker.thread)
	return true
}

@(private)
text_atlas_worker_stop :: proc(o: ^Overlay) {
	worker := &o.atlas_worker
	if worker.thread == nil {
		return
	}
	sync.lock(&worker.mutex)
	worker.quit = true
	sync.cond_signal(&worker.job_cond)
	sync.unlock(&worker.mutex)
	thread.join(worker.thread)
	thread.destroy(worker.thread)
	worker.thread = nil
	if worker.result_ready {
		text_atlas_destroy(&worker.result)
		worker.result_ready = false
	}
}

@(private)
text_atlas_worker_main :: proc(t: ^thread.Thread) {
	overlay := cast(^Overlay)t.data
	worker := &overlay.atlas_worker
	for {
		sync.lock(&worker.mutex)
		for !worker.job_pending && !worker.quit {
			sync.cond_wait(&worker.job_cond, &worker.mutex)
		}
		if worker.quit {
			sync.unlock(&worker.mutex)
			break
		}
		set := worker.job
		weight := worker.job_weight
		generation := worker.job_generation
		worker.job_pending = false
		worker.busy = true
		sync.unlock(&worker.mutex)

		atlas, built := text_atlas_build(context.allocator, &set, false)
		_ = mem.free_all(context.temp_allocator)

		sync.lock(&worker.mutex)
		worker.busy = false
		if !worker.quit && generation == worker.request_generation {
			if built {
				if worker.result_ready {
					text_atlas_destroy(&worker.result)
				}
				worker.result = atlas
				worker.result_weight = weight
				worker.result_ready = true
				worker.failed = false
			} else {
				worker.failed = true
			}
			sync.cond_signal(&worker.done_cond)
		} else if built {
			text_atlas_destroy(&atlas)
		}
		sync.unlock(&worker.mutex)
	}
}

