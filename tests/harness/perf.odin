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
}

@(test)
perf_command_rejects_bad_fields :: proc(t: ^testing.T) {
	lines := [3]string {
		`{"cmd": "perf", "nope": 1}`,
		`{"cmd": "perf", "frames": 0}`,
		`{"cmd": "perf", "warmup": -1}`,
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

	reply := execute(t, &session, `{"cmd": "perf", "frames": 5, "warmup": 0}`)
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
		`{"cmd": "perf", "frames": 3, "warmup": 0, "trace": "/tmp/opencode/harbagsa-perf-trace.jsonl"}`,
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

	reply := execute(t, &session, `{"cmd": "perf", "frames": 5, "warmup": 0}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "perf failed: %s", reply.error)
	testing.expect(t, reply.perf != nil, "reply has no perf object")
	if reply.perf != nil {
		testing.expect_value(t, reply.perf.measured, 5)
		testing.expect_value(t, reply.perf.warmup, 0)
		testing.expect(t, reply.perf.interval.p50 >= 0, "negative interval")
	}

	encoded := harness.encode_reply(reply)
	defer delete(encoded, context.allocator)
	text := string(encoded)
	testing.expect(t, strings.contains(text, `"perf"`), "reply JSON has no perf object")
	testing.expect(t, !strings.contains(text, `"gpu"`), "CPU-only reply has GPU fields")
}
