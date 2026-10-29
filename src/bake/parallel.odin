#+vet explicit-allocators
package bake

import "core:mem"
import "core:thread"

Parallel_Work :: struct {
	job: rawptr,
	run: proc(job: rawptr, worker: int),
}

// Each worker owns a disjoint subset of the output indices. Thread count and
// completion order therefore cannot change the result.
parallel_run :: proc(work: ^Parallel_Work, workers: int, allocator: mem.Allocator) -> bool {
	if workers < 1 {
		return false
	}
	if workers == 1 {
		work.run(work.job, 0)
		return true
	}
	threads := make([]^thread.Thread, workers - 1, allocator)
	defer delete(threads, allocator)

	created := 0
	for worker in 1 ..< workers {
		handle := thread.create(parallel_worker, .Normal, "bake")
		if handle == nil {
			for index in 0 ..< created {
				thread.join(threads[index])
				thread.destroy(threads[index])
			}
			return false
		}
		handle.data = work
		handle.user_index = worker
		threads[created] = handle
		created += 1
		thread.start(handle)
	}

	work.run(work.job, 0)
	for index in 0 ..< created {
		thread.join(threads[index])
		thread.destroy(threads[index])
	}
	return true
}

@(private)
parallel_worker :: proc(t: ^thread.Thread) {
	work := cast(^Parallel_Work)t.data
	work.run(work.job, t.user_index)
}
