#+vet explicit-allocators
package renderer

import "core:log"
import "core:time"

import "src:perf"
import vk "vendor:vulkan"

TIMESTAMP_COUNT :: u32(perf.PASS_COUNT) + 1

// Instrumentation never takes the renderer down: a pool that cannot be created
// turns the GPU timings off and leaves the CPU numbers in place.
init_timing :: proc(r: ^Renderer) {
	if !r.timing_available {
		return
	}
	info := vk.QueryPoolCreateInfo {
		sType      = .QUERY_POOL_CREATE_INFO,
		queryType  = .TIMESTAMP,
		queryCount = TIMESTAMP_COUNT,
	}
	for index in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !check(
			vk.CreateQueryPool(r.device, &info, nil, &r.query_pools[index]),
			"vkCreateQueryPool",
		) {
			log.warn("renderer: timestamp query pool creation failed; GPU timings are off")
			for pool in r.query_pools {
				if pool != 0 {
					vk.DestroyQueryPool(r.device, pool, nil)
				}
			}
			r.query_pools = {}
			r.timing_available = false
			return
		}
	}
}

destroy_timing :: proc(r: ^Renderer) {
	if r.device == nil {
		return
	}
	for pool in r.query_pools {
		if pool != 0 {
			vk.DestroyQueryPool(r.device, pool, nil)
		}
	}
	r.query_pools = {}
}

reset_timing :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer) {
	if !r.timing_available {
		return
	}
	vk.CmdResetQueryPool(command_buffer, r.query_pools[r.frame_index], 0, TIMESTAMP_COUNT)
}

write_timing_start :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer) {
	if !r.timing_available {
		return
	}
	vk.CmdWriteTimestamp(
		command_buffer,
		{.BOTTOM_OF_PIPE},
		r.query_pools[r.frame_index],
		0,
	)
}

// The timestamp index is the pass index plus one, so `perf.PASS_ORDER` is the
// only place the boundary order lives.
write_timing :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: perf.Pass) {
	if !r.timing_available {
		return
	}
	vk.CmdWriteTimestamp(
		command_buffer,
		{.BOTTOM_OF_PIPE},
		r.query_pools[r.frame_index],
		u32(pass) + 1,
	)
}

// The fence for this slot has already signalled, so the previous submission's
// timestamps are ready. The published sample keeps the frame it measured, and
// a failed read leaves the last completed sample in place.
read_timing :: proc(r: ^Renderer) {
	if !r.timing_available || !r.timing_valid[r.frame_index] {
		return
	}

	values: [TIMESTAMP_COUNT]u64
	result := vk.GetQueryPoolResults(
		r.device,
		r.query_pools[r.frame_index],
		0,
		TIMESTAMP_COUNT,
		size_of(values),
		&values[0],
		size_of(u64),
		{._64},
	)
	if result != .SUCCESS {
		return
	}

	mask := max(u64)
	if r.timestamp_valid_bits < 64 {
		mask = (u64(1) << uint(r.timestamp_valid_bits)) - 1
	}
	for &value in values {
		value &= mask
	}

	period := f64(r.timestamp_period)
	times := perf.Gpu_Times {
		available = true,
		frame     = r.timing_frames[r.frame_index],
	}
	previous := u32(0)
	for pass in perf.PASS_ORDER {
		next := u32(pass) + 1
		times.passes[pass] = ticks_duration(values[previous], values[next], period, mask)
		previous = next
	}
	times.total = ticks_duration(values[0], values[TIMESTAMP_COUNT - 1], period, mask)
	r.gpu_times = times
}

gpu_times :: proc(r: ^Renderer) -> perf.Gpu_Times {
	return r.gpu_times
}

// The counter can wrap inside a frame when the driver exposes fewer than 64
// valid bits, so the difference is masked, not the two readings.
ticks_duration :: proc(first, last: u64, period: f64, mask: u64) -> time.Duration {
	return time.Duration(f64((last - first) & mask) * period)
}
