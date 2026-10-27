#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
get_returns_the_scalar_type :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)

	number := execute(t, &session, `{"cmd":"get","field":"objects.count"}`)
	defer harness.reply_destroy(&number, context.allocator)
	testing.expectf(t, number.ok, "count get failed: %s", number.error)
	if number.ok {
		testing.expect_value(t, number.get.value.kind, harness.Value_Kind.Number)
		testing.expect_value(t, number.get.value.number, f64(6))
	}

	flag := execute(t, &session, `{"cmd":"get","field":"debug.active"}`)
	defer harness.reply_destroy(&flag, context.allocator)
	testing.expectf(t, flag.ok, "bool get failed: %s", flag.error)
	if flag.ok {
		testing.expect_value(t, flag.get.value.kind, harness.Value_Kind.Bool)
		testing.expect_value(t, flag.get.value.boolean, false)
	}

	text := execute(t, &session, `{"cmd":"get","field":"objects.1.prefab"}`)
	defer harness.reply_destroy(&text, context.allocator)
	testing.expectf(t, text.ok, "string get failed: %s", text.error)
	if text.ok {
		testing.expect_value(t, text.get.value.kind, harness.Value_Kind.String)
		testing.expect_value(t, text.get.value.text, "Crate")
	}
}

@(test)
get_names_an_unknown_field :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd":"get","field":"player.nope"}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, !reply.ok, "an unknown field succeeded")
	testing.expect(t, reply.error != "", "the failure has no message")
}
