#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import "src:game"

@(test)
a_scene_snapshot_notice_holds_for_two_seconds :: proc(t: ^testing.T) {
	hud: game.HUD_State
	game.hud_notice_scene_snapshot(&hud, "runs/repro/repro-1.json", true)
	testing.expect_value(t, game.hud_notice_text(&hud), "Scene snapshot · runs/repro/repro-1.json")
	testing.expect_value(t, hud.notice.remaining, game.NOTICE_SECONDS)

	game.hud_notice_update(&hud, 1.0)
	testing.expect_value(t, game.hud_notice_text(&hud), "Scene snapshot · runs/repro/repro-1.json")

	game.hud_notice_update(&hud, 1.1)
	testing.expect_value(t, game.hud_notice_text(&hud), "")
	testing.expect_value(t, hud.notice.remaining, 0)
}

@(test)
a_second_snapshot_restarts_the_hold_and_replaces_the_text :: proc(t: ^testing.T) {
	hud: game.HUD_State
	game.hud_notice_scene_snapshot(&hud, "runs/repro/a.json", true)
	game.hud_notice_update(&hud, 1.5)
	game.hud_notice_scene_snapshot(&hud, "runs/repro/b.json", false)
	testing.expect_value(t, game.hud_notice_text(&hud), "Scene snapshot failed · runs/repro/b.json")
	testing.expect_value(t, hud.notice.remaining, game.NOTICE_SECONDS)
}
