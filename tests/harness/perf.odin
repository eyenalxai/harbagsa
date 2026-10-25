#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:strings"
import "core:testing"

import "src:harness"

@(test)
perf_command_parses_defaults :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(`{"cmd": "perf"}`, context.allocator)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "parse failed: %s", error)
	testing.expect_value(t, command.kind, harness.Command_Kind.Perf)
	testing.expect_value(t, command.perf.frames, harness.PERF_DEFAULT_FRAMES)
	testing.expect_value(t, command.perf.warmup, harness.PERF_DEFAULT_WARMUP)
	testing.expect_value(t, command.perf.prime, harness.PERF_DEFAULT_PRIME)
	testing.expect_value(t, command.perf.name, "perf")
}

@(test)
perf_command_rejects_bad_fields :: proc(t: ^testing.T) {
	lines := [6]string {
		`{"cmd": "perf", "nope": 1}`,
		`{"cmd": "perf", "frames": 0}`,
		`{"cmd": "perf", "warmup": -1}`,
		`{"cmd": "perf", "prime": -1}`,
		`{"cmd": "perf", "prime": 61}`,
		`{"cmd": "perf", "name": "two words"}`,
	}
	for line in lines {
		command, error := harness.command_parse_string(line, context.allocator)
		harness.command_destroy(&command, context.allocator)
		rejected := error != ""
		if rejected {
			delete(error, context.allocator)
		}
		testing.expectf(t, rejected, "accepted %s", line)
	}
}

@(test)
perf_does_not_change_the_state_digest :: proc(t: ^testing.T) {
	first := perf_digest(t)
	defer delete(first, context.allocator)
	second := perf_digest(t)
	defer delete(second, context.allocator)
	testing.expect_value(t, first, second)
}

@(private)
perf_digest :: proc(t: ^testing.T) -> string {
	session, create_error := harness.session_create(context.allocator)
	testing.expectf(t, create_error == "", "session failed: %s", create_error)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "perf", "frames": 5, "warmup": 0, "prime": 0}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "perf failed: %s", reply.error)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	return strings.clone(state.digest, context.allocator)
}

@(test)
perf_trace_writes_jsonl :: proc(t: ^testing.T) {
	session, create_error := harness.session_create(context.allocator)
	testing.expectf(t, create_error == "", "session failed: %s", create_error)
	defer harness.session_destroy(&session)

	path := "/tmp/opencode/harbagsa-perf-trace.jsonl"
	_ = os.remove(path)
	reply := execute(
		t,
		&session,
		`{"cmd": "perf", "frames": 3, "warmup": 0, "prime": 0, "trace": "/tmp/opencode/harbagsa-perf-trace.jsonl"}`,
	)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "perf failed: %s", reply.error)

	trace_error := harness.write_session_trace(&session, "/tmp/opencode")
	testing.expectf(t, trace_error == "", "trace failed: %s", trace_error)
	if trace_error != "" {
		delete(trace_error, context.allocator)
		return
	}

	data, read_error := os.read_entire_file(path, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read the trace: %v", read_error)
	if read_error != nil {
		return
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	count := 0
	for line in lines {
		if line == "" {
			continue
		}
		count += 1
		testing.expect(t, strings.contains(line, `"frame"`), "trace line has no frame")
		testing.expect(t, strings.contains(line, `"interval"`), "trace line has no interval")
		testing.expect(t, strings.contains(line, `"cpu"`), "trace line has no CPU phases")
		testing.expect(t, !strings.contains(line, `"gpu"`), "CPU-only trace has GPU fields")
	}
	testing.expect_value(t, count, 3)
	_ = os.remove(path)
}

@(test)
perf_runs_without_a_device :: proc(t: ^testing.T) {
	session, create_error := harness.session_create(context.allocator)
	testing.expectf(t, create_error == "", "session failed: %s", create_error)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "perf", "frames": 5, "warmup": 0, "prime": 0}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "perf failed: %s", reply.error)
	testing.expect(t, reply.perf != nil, "reply has no perf object")
	if reply.perf != nil {
		testing.expect_value(t, reply.perf.measured, 5)
		testing.expect_value(t, reply.perf.warmup, 0)
		testing.expect_value(t, reply.perf.name, "perf")
		testing.expect(t, reply.perf.interval.p50 >= 0, "negative interval")
	}

	encoded := harness.encode_reply(reply)
	defer delete(encoded, context.allocator)
	text := string(encoded)
	testing.expect(t, strings.contains(text, `"perf"`), "reply JSON has no perf object")
	testing.expect(t, !strings.contains(text, `"gpu"`), "CPU-only reply has GPU fields")
}

@(test)
perf_prime_runs_before_the_measured_window :: proc(t: ^testing.T) {
	session, create_error := harness.session_create(context.allocator)
	testing.expectf(t, create_error == "", "session failed: %s", create_error)
	defer harness.session_destroy(&session)

	reply := execute(
		t,
		&session,
		`{"cmd": "perf", "frames": 3, "warmup": 0, "prime": 0.01}`,
	)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "perf failed: %s", reply.error)
	if reply.perf == nil {
		return
	}
	testing.expect_value(t, reply.perf.measured, 3)
	testing.expect_value(t, reply.perf.prime_seconds, 0.01)
	testing.expect(t, reply.perf.prime_frames >= 1, "the prime loop ran no frames")
	testing.expect(t, reply.perf.prime_frames <= harness.MAX_PERF_PRIME_FRAMES, "the prime loop ran too long")
}

@(test)
perf_names_accumulate_in_the_session :: proc(t: ^testing.T) {
	session, create_error := harness.session_create(context.allocator)
	testing.expectf(t, create_error == "", "session failed: %s", create_error)
	defer harness.session_destroy(&session)

	first := execute(
		t,
		&session,
		`{"cmd": "perf", "frames": 2, "warmup": 0, "prime": 0, "name": "first"}`,
	)
	harness.reply_destroy(&first, context.allocator)
	second := execute(
		t,
		&session,
		`{"cmd": "perf", "frames": 2, "warmup": 0, "prime": 0, "name": "second"}`,
	)
	defer harness.reply_destroy(&second, context.allocator)
	testing.expectf(t, second.ok, "second perf failed: %s", second.error)

	testing.expect_value(t, len(session.perf.reports), 2)
	if len(session.perf.reports) == 2 {
		testing.expect_value(t, session.perf.reports[0].name, "first")
		testing.expect_value(t, session.perf.reports[1].name, "second")
	}
	if second.perf != nil {
		testing.expect_value(t, second.perf.name, "second")
	}
}

@(test)
perf_rejects_a_second_trace :: proc(t: ^testing.T) {
	session, create_error := harness.session_create(context.allocator)
	testing.expectf(t, create_error == "", "session failed: %s", create_error)
	defer harness.session_destroy(&session)

	first := execute(
		t,
		&session,
		`{"cmd": "perf", "frames": 2, "warmup": 0, "prime": 0, "trace": "/tmp/opencode/perf-one.jsonl"}`,
	)
	harness.reply_destroy(&first, context.allocator)
	second := execute(
		t,
		&session,
		`{"cmd": "perf", "frames": 2, "warmup": 0, "prime": 0, "trace": "/tmp/opencode/perf-two.jsonl"}`,
	)
	defer harness.reply_destroy(&second, context.allocator)
	testing.expect(t, !second.ok, "a second perf trace was accepted")
	testing.expect(t, strings.contains(second.error, "one perf trace"), "missing the trace limit error")
}

@(test)
perf_reports_distributions_for_the_cpu_phases :: proc(t: ^testing.T) {
	session, create_error := harness.session_create(context.allocator)
	testing.expectf(t, create_error == "", "session failed: %s", create_error)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "perf", "frames": 3, "warmup": 0, "prime": 0}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "perf failed: %s", reply.error)
	if reply.perf == nil {
		return
	}
	testing.expect(t, reply.perf.cpu.events.p50 >= 0, "the CPU p50 is negative")
	testing.expect(t, reply.perf.cpu.events.p95 >= reply.perf.cpu.events.p50, "the CPU p95 is below p50")
	testing.expect(t, reply.perf.cpu.events.mean >= 0, "the CPU mean is negative")
}
