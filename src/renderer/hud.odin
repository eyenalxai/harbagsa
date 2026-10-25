#+vet explicit-allocators
package renderer

import "core:math"

import "src:ui"

HUD_Frame :: struct {
	enabled:      bool,
	menu_open:    bool,
	view:         ui.Hud,
	capture_hint: string,
	captured:     bool,
	menu:         ui.Menu,
	palette:      ui.Palette,
	weight:       f32,
}

hud_emit_textured_quad :: proc(
	o: ^Overlay,
	a, b, c, d: [2]f32,
	uv0, uv1: [2]f32,
	color: [4]f32,
) {
	append_hud_vertex(o, a, color, uv0)
	append_hud_vertex(o, b, color, {uv1.x, uv0.y})
	append_hud_vertex(o, c, color, uv1)
	append_hud_vertex(o, a, color, uv0)
	append_hud_vertex(o, c, color, uv1)
	append_hud_vertex(o, d, color, {uv0.x, uv1.y})
}

hud_emit_quad :: proc(o: ^Overlay, a, b, c, d: [2]f32, color: [4]f32) {
	hud_emit_textured_quad(o, a, b, c, d, TEXT_UV_NONE, TEXT_UV_NONE, color)
}

hud_emit_rect :: proc(o: ^Overlay, x, y, width, height: f32, color: [4]f32) {
	if width <= 0 || height <= 0 {
		return
	}
	hud_emit_quad(
		o,
		{x, y},
		{x + width, y},
		{x + width, y + height},
		{x, y + height},
		color,
	)
}

// A translucent surface cannot be given a border by filling a larger rect, so
// the hairline is drawn as four edges. The sides span the inner height: a full
// height side would blend its ends twice at the corners.
hud_emit_frame :: proc(o: ^Overlay, x, y, width, height, thickness: f32, color: [4]f32) {
	hud_emit_rect(o, x, y, width, thickness, color)
	hud_emit_rect(o, x, y + height - thickness, width, thickness, color)
	hud_emit_rect(o, x, y + thickness, thickness, height - thickness * 2, color)
	hud_emit_rect(o, x + width - thickness, y + thickness, thickness, height - thickness * 2, color)
}

hud_crosshair_reach :: proc(theme: UI_Theme) -> f32 {
	return theme.crosshair_gap + theme.crosshair_arm + theme.hairline
}

build_hud :: proc(o: ^Overlay, width, height: f32, hud: HUD_Frame) {
	if !hud.enabled {
		return
	}
	if hud.menu_open {
		build_menu(o, width, height, hud.menu)
		return
	}

	build_status_panel(o, hud.view)
	build_notice(o, width, hud.view.notice)
	if hud.palette.open {
		build_palette(o, width, height, hud.palette)
	}
	build_capture_hint(o, width, height, hud)
	build_crosshair(o, width * 0.5, height * 0.5)
}

@(private)
build_status_panel :: proc(o: ^Overlay, view: ui.Hud) {
	theme := o.theme
	rows := view.rows
	if len(rows) == 0 {
		return
	}
	padding := theme.spacing.lg
	options := ui.Rows_Options{value_align = .Left}
	ctx: Layout_Context
	layout_context_init(&ctx, theme, &o.atlas, 0, 0)
	layout := ui.rows_layout(ctx.inputs, rows, options)

	x := theme.spacing.md
	y := theme.spacing.md
	width := layout.width + padding * 2
	height := layout.height + padding * 2

	hud_emit_rect(o, x, y, width, height, theme.surface_hud)
	hud_emit_frame(o, x, y, width, height, theme.hairline, theme.line_hairline)
	rows_emit(o, theme, x + padding, y + padding, ctx.inputs, layout, rows, options)
}

@(private)
build_capture_hint :: proc(o: ^Overlay, width, height: f32, hud: HUD_Frame) {
	if hud.captured || hud.capture_hint == "" || hud.palette.open {
		return
	}
	theme := o.theme
	padding := theme.spacing.md
	style := Text_Style{type = theme.type_body, color = theme.text_primary}
	text_width := text_measure(&o.atlas, style.type, hud.capture_hint)
	box_width := text_width + padding * 2
	box_height := style.type.line_height + padding * 2
	box_x := (width - box_width) * 0.5
	// Below the crosshair, so the arms never cut through the text.
	box_y := height * 0.5 + hud_crosshair_reach(theme) + theme.spacing.md

	hud_emit_rect(o, box_x, box_y, box_width, box_height, theme.surface_hud)
	hud_emit_frame(o, box_x, box_y, box_width, box_height, theme.hairline, theme.line_hairline)
	text_emit(
		o,
		box_x + padding,
		box_y + padding + text_baseline(&o.atlas, style.type),
		style,
		hud.capture_hint,
	)
}

@(private)
build_crosshair :: proc(o: ^Overlay, center_x, center_y: f32) {
	theme := o.theme
	arm := hud_snap(theme.crosshair_arm)
	gap := hud_snap(theme.crosshair_gap)
	thickness := theme.hairline

	// The crosshair is emitted last so it stays on top of the panels. Its edges
	// snap to whole pixels: a hairline on a fraction turns into two grey ones.
	hud_crosshair_arm(
		o,
		hud_snap(center_x - gap - arm),
		hud_snap(center_y - thickness * 0.5),
		arm,
		thickness,
	)
	hud_crosshair_arm(
		o,
		hud_snap(center_x + gap),
		hud_snap(center_y - thickness * 0.5),
		arm,
		thickness,
	)
	hud_crosshair_arm(
		o,
		hud_snap(center_x - thickness * 0.5),
		hud_snap(center_y - gap - arm),
		thickness,
		arm,
	)
	hud_crosshair_arm(
		o,
		hud_snap(center_x - thickness * 0.5),
		hud_snap(center_y + gap),
		thickness,
		arm,
	)
}

hud_snap :: proc(value: f32) -> f32 {
	return math.round(value)
}

@(private)
hud_crosshair_arm :: proc(o: ^Overlay, x, y, width, height: f32) {
	theme := o.theme
	outline := theme.hairline
	hud_emit_rect(
		o,
		x - outline,
		y - outline,
		width + outline * 2,
		height + outline * 2,
		theme.crosshair_edge,
	)
	hud_emit_rect(o, x, y, width, height, theme.crosshair)
}
