#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:strings"
import "core:testing"

import "src:game"
import "src:harness"

@(test)
displays_set_and_clear_the_list :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	reply := execute(
		t,
		&session,
		`{"cmd":"displays","set":[{"name":"Solo","desktop":"1280x720","modes":["1280x720"]}]}`,
	)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, reply.ok, "displays set failed")
	testing.expect(t, reply.displays != nil, "the reply has no display list")
	if reply.displays != nil {
		testing.expect_value(t, reply.displays.count, 1)
		testing.expect_value(t, reply.displays.displays[0].name, "Solo")
	}
	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.settings.display, "Solo")
	testing.expect_value(t, state.settings.display_index, 0)
	testing.expect_value(t, state.settings.resolution, "1280x720")

	cleared := execute(t, &session, `{"cmd":"displays","clear":true}`)
	defer harness.reply_destroy(&cleared, context.allocator)
	testing.expect(t, cleared.ok, "displays clear failed")
	restored := harness.session_state(&session)
	defer harness.state_destroy(&restored, context.allocator)
	testing.expect_value(t, restored.settings.display_index, 0)
	testing.expect(t, cleared.displays != nil && cleared.displays.count == 2, "clear did not restore the fallback list")
}

@(test)
displays_accept_a_zero_mode_display :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	reply := execute(t, &session, `{"cmd":"displays","set":[{"name":"Solo"}]}`)
	harness.reply_destroy(&reply, context.allocator)
	menu := execute(t, &session, `{"cmd":"menu","open":true,"item":"Resolution","activate":true}`)
	defer harness.reply_destroy(&menu, context.allocator)
	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.settings.resolution, "0x0")
	testing.expect_value(t, state.menu.status, game.MENU_STATUS_NO_MODES)
	testing.expect(t, state.menu.blocked, "the Resolution row is not blocked")
	testing.expect(t, len(state.rows.menu) > 2, "the menu row dump is missing")
	if len(state.rows.menu) > 2 {
		testing.expect_value(t, state.rows.menu[2].blocked, true)
	}
}

@(test)
displays_one_mode_is_blocked_in_borderless :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	reply := execute(
		t,
		&session,
		`{"cmd":"displays","set":[{"name":"Solo","desktop":"1280x720","modes":["1280x720"]}]}`,
	)
	harness.reply_destroy(&reply, context.allocator)
	// Borderless uses the desktop mode, so one mode is not blocked until the
	// window is Windowed.
	menu := execute(t, &session, `{"cmd":"menu","open":true,"item":"Window mode","activate":true}`)
	harness.reply_destroy(&menu, context.allocator)
	blocked := execute(t, &session, `{"cmd":"menu","item":"Resolution","activate":true}`)
	harness.reply_destroy(&blocked, context.allocator)
	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.settings.window_mode, "Windowed")
	testing.expect(t, state.menu.blocked, "a one-mode Windowed display is not blocked")
}

@(test)
displays_reject_bad_lists :: proc(t: ^testing.T) {
	bad_lists := []string{
		`{"cmd":"displays","clear":true,"set":[{"name":"Solo"}]}`,
		`{"cmd":"displays"}`,
		`{"cmd":"displays","set":[]}`,
		`{"cmd":"displays","set":[{"name":"Solo","desktop":"wide"}]}`,
		`{"cmd":"displays","set":[{"name":"Solo","modes":["1280x720","bad"]}]}`,
	}
	for line in bad_lists {
		_, parse_error := harness.command_parse_string(line, context.allocator)
		testing.expectf(t, parse_error != "", "bad display list accepted: %s", line)
		if parse_error != "" {
			delete(parse_error, context.allocator)
		}
	}
}

@(test)
displays_report_the_clamped_index :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}
	// Move the menu to the second fallback display, then replace the list with
	// one display; every read must clamp the stored index.
	reply := execute(t, &session, `{"cmd":"menu","open":true,"item":"Display","activate":true}`)
	harness.reply_destroy(&reply, context.allocator)
	state := harness.session_state(&session)
	testing.expect_value(t, state.settings.display_index, 1)
	harness.state_destroy(&state, context.allocator)

	reply = execute(t, &session, `{"cmd":"displays","set":[{"name":"Solo"}]}`)
	harness.reply_destroy(&reply, context.allocator)
	clamped := harness.session_state(&session)
	defer harness.state_destroy(&clamped, context.allocator)
	testing.expect_value(t, clamped.settings.display_index, 0)
	testing.expect_value(t, clamped.settings.display, "Solo")
	_ = strings.contains("", "")
}
