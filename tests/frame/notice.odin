#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:frame"
import "src:game"
import "src:renderer"
import "src:ui"

NOTICE_TEXT :: "Scene snapshot · runs/repro/repro-1760000000.json"
NOTICE_FAILED :: "Scene snapshot failed · runs/repro/repro-1760000000.json"

@(test)
a_notice_is_one_padded_body_line_on_the_top_right_margin :: proc(t: ^testing.T) {
	inputs := fake_inputs()
	layout := ui.notice_layout(inputs, ui.Notice{text = NOTICE_FAILED})
	testing.expect(t, layout.box.width > 0, "the notice has no box")
	testing.expect_value(
		t,
		layout.box.x + layout.box.width,
		inputs.width - inputs.spacing.md,
	)
	testing.expect_value(t, layout.box.y, inputs.spacing.md)
	testing.expect_value(
		t,
		layout.box.height,
		fake_line_height(nil, .Body) + inputs.spacing.md * 2,
	)
	testing.expect_value(t, layout.text_x, layout.box.x + inputs.spacing.md)
	testing.expect_value(
		t,
		layout.baseline,
		layout.box.y + inputs.spacing.md + fake_baseline(nil, .Body),
	)
}

@(test)
an_empty_notice_has_no_layout :: proc(t: ^testing.T) {
	testing.expect_value(t, ui.notice_layout(fake_inputs(), ui.Notice{}), ui.Notice_Layout{})
}

@(test)
the_notice_buffer_holds_a_full_path_and_the_failure_copy :: proc(t: ^testing.T) {
	testing.expect(
		t,
		len("Scene snapshot failed · ") + frame.SNAPSHOT_PATH_BYTES <= game.NOTICE_TEXT_BYTES,
		"a full path plus the failure copy does not fit the notice buffer",
	)
}

@(test)
the_notice_keeps_clear_of_the_status_panel_at_the_smallest_window :: proc(t: ^testing.T) {
	sim, debug, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	theme := renderer.ui_theme_init(600)
	atlas, built := build_atlas(t, theme)
	testing.expect(t, built, "the atlas did not build")
	if !built {
		return
	}
	defer renderer.text_atlas_destroy(&atlas)
	overlay := renderer.Overlay {
		atlas = atlas,
		theme = theme,
	}
	overlay.hud_vertices = make([]renderer.HUD_Vertex, 4096, context.allocator)
	defer delete(overlay.hud_vertices, context.allocator)

	snapshot := game.simulation_snapshot(&sim)
	game.hud_state_update(&hud, &sim, &debug, snapshot, true, 0)
	game.hud_notice_scene_snapshot(&hud, "runs/repro/repro-1760000000.json", false)
	game.hud_state_update(&hud, &sim, &debug, snapshot, true, 0)
	renderer.build_hud(
		&overlay,
		800,
		600,
		renderer.HUD_Frame{enabled = true, view = hud.view},
	)

	surfaces: [16]Rect
	count := quads_with(overlay, theme.surface_hud, surfaces[:])
	panel: Rect
	notice: Rect
	for quad in surfaces[:count] {
		if quad.x == theme.spacing.md {
			panel = quad
		} else if quad.y == theme.spacing.md {
			notice = quad
		}
	}
	testing.expect(t, panel.width > 0, "the status panel is missing")
	testing.expect(t, notice.width > 0, "the notice is missing")
	testing.expectf(
		t,
		notice.x >= panel.x + panel.width,
		"the notice %v overlaps the panel %v",
		notice,
		panel,
	)
	testing.expect_value(t, notice.x + notice.width, 800 - theme.spacing.md)
}

@(test)
the_menu_hides_the_notice :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(720)
	atlas, built := build_atlas(t, theme)
	testing.expect(t, built, "the atlas did not build")
	if !built {
		return
	}
	defer renderer.text_atlas_destroy(&atlas)
	overlay := renderer.Overlay {
		atlas = atlas,
		theme = theme,
	}
	overlay.hud_vertices = make([]renderer.HUD_Vertex, 24576, context.allocator)
	defer delete(overlay.hud_vertices, context.allocator)

	renderer.build_hud(
		&overlay,
		1280,
		720,
		renderer.HUD_Frame {
			enabled = true,
			menu_open = true,
			view = ui.Hud{notice = ui.Notice{text = NOTICE_TEXT}},
			menu = ui.Menu{title = "Settings"},
		},
	)
	surfaces: [8]Rect
	testing.expect_value(t, quads_with(overlay, theme.surface_hud, surfaces[:]), 0)
}

@(test)
the_frame_carries_the_notice_from_the_hud :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	game.hud_notice_scene_snapshot(&hud, "runs/repro/repro-1.json", true)
	scene := frame.build(&sim, &debug, {alpha = 1.0, hud = true}, nil, &hud, &scratch)
	testing.expect_value(
		t,
		scene.hud.view.notice.text,
		"Scene snapshot · runs/repro/repro-1.json",
	)
}
