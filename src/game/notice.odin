#+vet explicit-allocators
#+vet !unused-procedures // the F5 key and the harness set a notice
package game

import "core:fmt"

NOTICE_SECONDS :: 2.0
// The longest copy is "Scene snapshot failed · " plus a snapshot path of at
// most frame.SNAPSHOT_PATH_BYTES.
NOTICE_TEXT_BYTES :: 224

Notice_State :: struct {
	text:      [NOTICE_TEXT_BYTES]u8,
	length:    int,
	remaining: f32,
}

// The key writes a file the player cannot see, so the result is drawn. A failed
// write keeps the same colours and says so in words, because a colour is never
// the only signal.
hud_notice_scene_snapshot :: proc(hud: ^HUD_State, path: string, ok: bool) {
	format := ok ? "Scene snapshot · %s" : "Scene snapshot failed · %s"
	written := fmt.bprintf(hud.notice.text[:], format, path)
	hud.notice.length = len(written)
	hud.notice.remaining = NOTICE_SECONDS
}

hud_notice_update :: proc(hud: ^HUD_State, delta_seconds: f32) {
	if hud.notice.length == 0 {
		return
	}
	hud.notice.remaining = max(hud.notice.remaining - delta_seconds, 0)
	if hud.notice.remaining <= 0 {
		hud.notice = {}
	}
}

hud_notice_text :: proc(hud: ^HUD_State) -> string {
	if hud.notice.length == 0 {
		return ""
	}
	return string(hud.notice.text[:hud.notice.length])
}
