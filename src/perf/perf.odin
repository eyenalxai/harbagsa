#+vet explicit-allocators
#+vet !unused-procedures // main calls this API; library checks compile perf as a dependency
package perf

import "core:time"

RING_CAPACITY :: 600
STATS_REFRESH_FRAMES :: 15

Mark :: enum u8 {
	Frame_Start,
	Events,
	Simulation,
	Build,
	Record,
	Present,
}

Phase :: enum u8 {
	Events,
	Simulation,
	Build,
	Record,
	Present,
}

Pass :: enum u8 {
	Tlas,
	Depth,
	Scene,
	Sky,
	Taa,
	Overlay,
}

PHASE_COUNT :: int(Phase.Present) + 1
MARK_COUNT :: int(Mark.Present) + 1
PASS_COUNT :: int(Pass.Overlay) + 1

Gpu_Times :: struct {
	available: bool,
	frame:     u64,
	passes:    [Pass]time.Duration,
	total:     time.Duration,
}

ALL_MARKS :: bit_set[Mark] {
	.Frame_Start,
	.Events,
	.Simulation,
	.Build,
	.Record,
	.Present,
}

Sample :: struct {
	frame:    u64,
	interval: time.Duration,
	phases:   [Phase]time.Duration,
	gpu:      Gpu_Times,
}

Summary :: struct {
	measured: int,
	warmup:   int,
	stats:    Stats,
}

Ring :: struct {
	samples: [RING_CAPACITY]Sample,
	next:    int,
	count:   int,
}

ring_push :: proc(ring: ^Ring, sample: Sample) {
	ring.samples[ring.next] = sample
	ring.next = (ring.next + 1) % RING_CAPACITY
	ring.count = min(ring.count + 1, RING_CAPACITY)
}

// The recorder accepts the six marks in order. The renderer owns the record
// mark, so it sees only this type and cannot reach the ring or the statistics.
Recorder :: struct {
	marks: [Mark]time.Tick,
	used:  bit_set[Mark],
}

recorder_begin :: proc(recorder: ^Recorder, start: time.Tick) {
	recorder.marks = {}
	recorder.used = {.Frame_Start}
	recorder.marks[.Frame_Start] = start
}

recorder_mark :: proc(recorder: ^Recorder, mark: Mark) {
	recorder.marks[mark] = time.tick_now()
	recorder.used += {mark}
}

recorder_complete :: proc(recorder: ^Recorder) -> bool {
	if recorder.used != ALL_MARKS {
		return false
	}
	for index in 1 ..< MARK_COUNT {
		previous := recorder.marks[Mark(index - 1)]
		next := recorder.marks[Mark(index)]
		if time.tick_diff(previous, next) < 0 {
			return false
		}
	}
	return true
}

recorder_has :: proc(recorder: ^Recorder, mark: Mark) -> bool {
	return mark in recorder.used
}

State :: struct {
	recorder:     Recorder,
	ring:         Ring,
	frame:        u64,
	previous:     time.Tick,
	has_previous: bool,
	interval:     time.Duration,
	gpu:          Gpu_Times,
	stats:        Stats,
	stats_frame:  u64,
	stats_valid:  bool,
}

begin_frame :: proc(state: ^State) {
	now := time.tick_now()
	state.frame += 1
	state.interval = 0
	state.gpu = {}
	if state.has_previous {
		state.interval = time.tick_diff(state.previous, now)
	}
	state.previous = now
	state.has_previous = true
	recorder_begin(&state.recorder, now)
}

mark :: proc(state: ^State, mark: Mark) {
	recorder_mark(&state.recorder, mark)
}

set_gpu :: proc(state: ^State, times: Gpu_Times) {
	state.gpu = times
}

end_frame :: proc(state: ^State) {
	if !recorder_complete(&state.recorder) || state.interval <= 0 {
		return
	}

	sample := Sample {
		frame    = state.frame,
		interval = state.interval,
		gpu      = state.gpu,
	}
	for i in 0 ..< PHASE_COUNT {
		phase := Phase(i)
		first, last := phase_marks(phase)
		sample.phases[phase] = time.tick_diff(
			state.recorder.marks[first],
			state.recorder.marks[last],
		)
	}
	ring_push(&state.ring, sample)
}

// A minimized window waits for events outside the frame budget. Dropping the
// interval keeps that wait out of the next sample.
discard_frame :: proc(state: ^State) {
	state.has_previous = false
	state.interval = 0
	state.recorder.used = {}
}

stats :: proc(state: ^State) -> Stats {
	if !state.stats_valid || state.frame - state.stats_frame >= STATS_REFRESH_FRAMES {
		state.stats = stats_from_ring(&state.ring)
		state.stats_frame = state.frame
		state.stats_valid = true
	}
	return state.stats
}

last_sample :: proc(state: ^State) -> (Sample, bool) {
	if state.ring.count == 0 {
		return {}, false
	}
	index := (state.ring.next - 1 + RING_CAPACITY) % RING_CAPACITY
	return state.ring.samples[index], true
}

phase_marks :: proc(phase: Phase) -> (first, last: Mark) {
	switch phase {
	case .Events:
		return .Frame_Start, .Events
	case .Simulation:
		return .Events, .Simulation
	case .Build:
		return .Simulation, .Build
	case .Record:
		return .Build, .Record
	case .Present:
		return .Record, .Present
	}
	return .Frame_Start, .Events
}
