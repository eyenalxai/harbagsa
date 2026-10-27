#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:os"
import "core:strings"
import "core:testing"

import "src:game"
import "src:harness"

MENU_RECORD_PATH :: "/tmp/opencode/harbagsa-menu-record-test.json"

@(test)
menu_command_opens_selects_and_toggles :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	if error != "" {
		return
	}

	reply := execute(t, &session, `{"cmd": "menu", "open": true}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, session.hud.menu.open, "menu did not open")

	reply = execute(t, &session, `{"cmd": "menu", "item": "Sprint mode"}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, session.hud.menu.selected, game.Menu_Item.Sprint)

	reply = execute(t, &session, `{"cmd": "menu", "activate": true}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect_value(t, session.sim.settings.sprint_mode, game.Input_Mode.Toggle)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.settings.sprint_mode, "Toggle")
	testing.expect(t, state.menu.open, "state did not report the open menu")
	testing.expect_value(t, state.menu.item, "Sprint mode")

	reply = execute(t, &session, `{"cmd": "menu", "open": false}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, !session.hud.menu.open, "menu did not close")
}

@(test)
step_is_rejected_while_the_menu_is_open :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "menu", "open": true}`)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "step", "frames": 1}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, !reply.ok, "step advanced while the menu was open")
	testing.expect(t, strings.contains(reply.error, "menu is open"), "missing pause error")
	testing.expect_value(t, session.frame, 0)
}

@(test)
menu_and_settings_are_checkable :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "menu", "open": true}`)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "check", "field": "menu.open", "op": "eq", "value": true}`)
	first_ok := reply.ok
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, first_ok, "menu.open check failed")

	reply = execute(
		t,
		&session,
		`{"cmd": "check", "field": "settings.sprint_mode", "op": "eq", "value": "Hold"}`,
	)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, reply.ok, "settings.sprint_mode check failed")
}

@(test)
menu_changes_the_state_digest :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	before := harness.session_state(&session)
	defer harness.state_destroy(&before, context.allocator)

	reply := execute(t, &session, `{"cmd": "menu", "open": true, "item": "Window mode"}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "menu", "activate": true}`)
	harness.reply_destroy(&reply, context.allocator)

	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	testing.expect(t, after.digest != before.digest, "settings or menu did not change the digest")
}

@(test)
menu_activate_false_is_accepted :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "menu", "open": true}`)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "menu", "activate": false}`)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, reply.ok, "activate:false was rejected")
}

@(test)
rejected_menu_command_leaves_the_menu_unchanged :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "menu", "open": true, "item": "Sprint mode"}`)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "menu", "open": false, "item": "Sprint mode"}`)
	harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, session.hud.menu.open, "a rejected command closed the menu")
	testing.expect_value(t, session.hud.menu.selected, game.Menu_Item.Sprint)
}

@(test)
reset_restores_the_menu_and_the_settings :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)
	reply := execute(t, &session, `{"cmd": "menu", "open": true, "item": "Sprint mode"}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "menu", "activate": true}`)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(t, &session, `{"cmd": "reset"}`)
	harness.reply_destroy(&reply, context.allocator)
	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect(t, !state.menu.open, "reset left the menu open")
	testing.expect_value(t, state.menu.item, "Window mode")
	testing.expect_value(t, state.settings.sprint_mode, "Hold")
}

@(test)
menu_commands_replay_to_the_same_digest :: proc(t: ^testing.T) {
	_ = os.remove(MENU_RECORD_PATH)
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)

	record_line := strings.concatenate(
		{`{"cmd": "record", "path": "`, MENU_RECORD_PATH, `"}`},
		context.temp_allocator,
	)
	reply := execute(t, &session, record_line)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "menu", "open": true, "item": "Window mode"}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "menu", "activate": true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "menu", "open": false}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "step", "frames": 10}`)
	harness.reply_destroy(&reply, context.allocator)

	before := harness.session_state(&session)
	defer harness.state_destroy(&before, context.allocator)
	reply = execute(t, &session, `{"cmd": "record"}`)
	harness.reply_destroy(&reply, context.allocator)

	replay_line := strings.concatenate(
		{`{"cmd": "replay", "path": "`, MENU_RECORD_PATH, `"}`},
		context.temp_allocator,
	)
	reply = execute(t, &session, replay_line)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "replay failed: %s", reply.error)
	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	testing.expect_value(t, after.digest, before.digest)
}

@(test)
window_settings_are_reported_and_checkable :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.settings.window_mode, "Borderless")
	testing.expect_value(t, state.settings.display, "Display 1")
	testing.expect_value(t, state.settings.display_index, 0)
	testing.expect_value(t, state.settings.resolution, "1920x1080")
	testing.expect_value(t, state.settings.window_resolution, "1280x720")

	reply := execute(t, &session, `{"cmd": "menu", "open": true, "item": "Window mode", "activate": true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "menu", "item": "Resolution", "activate": true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(t, &session, `{"cmd": "menu", "item": "Display", "activate": true}`)
	harness.reply_destroy(&reply, context.allocator)

	after := harness.session_state(&session)
	defer harness.state_destroy(&after, context.allocator)
	testing.expect_value(t, after.settings.window_mode, "Windowed")
	testing.expect_value(t, after.settings.display, "Display 2")
	testing.expect_value(t, after.settings.display_index, 1)
	testing.expect_value(t, after.settings.resolution, "1920x1080")
	testing.expect_value(t, after.settings.window_resolution, "1920x1080")

	reply = execute(
		t,
		&session,
		`{"cmd": "check", "field": "settings.window_mode", "op": "eq", "value": "Windowed"}`,
	)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expect(t, reply.ok, "settings.window_mode check failed")
}

@(test)
menu_activate_direction_moves_backward :: proc(t: ^testing.T) {
	session, _ := harness.session_create(context.allocator)
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd": "menu", "open": true, "item": "Window mode", "activate": true}`)
	harness.reply_destroy(&reply, context.allocator)
	reply = execute(
		t,
		&session,
		`{"cmd": "menu", "item": "Resolution", "activate": true, "direction": -1}`,
	)
	harness.reply_destroy(&reply, context.allocator)

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, state.settings.window_mode, "Windowed")
	testing.expect_value(t, state.settings.resolution, "1600x900")
}

@(test)
menu_direction_needs_activate :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd": "menu", "item": "Resolution", "direction": -1}`,
		context.allocator,
	)
	if error == "" {
		harness.command_destroy(&command, context.allocator)
	}
	testing.expect(t, error != "", "direction without activate was accepted")
	testing.expect(t, strings.contains(error, "direction"), "missing direction error")
	if error != "" {
		delete(error, context.allocator)
	}
}
