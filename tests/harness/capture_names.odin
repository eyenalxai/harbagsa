#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
session_rejects_a_duplicate_capture_name :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	calls: int
	backend := harness.Backend {
		ready  = true,
		ctx    = &calls,
		render = fake_render,
	}
	harness.session_set_backend(&session, &backend, false)

	first := execute(t, &session, `{"cmd":"capture","name":"same"}`)
	testing.expectf(t, first.ok, "the first capture failed: %s", first.error)
	harness.reply_destroy(&first, context.allocator)
	second := execute(t, &session, `{"cmd":"capture","name":"same"}`)
	defer harness.reply_destroy(&second, context.allocator)
	testing.expect(t, !second.ok, "a duplicate capture name was accepted")
	testing.expect(t, second.error != "", "the duplicate error is empty")
}
