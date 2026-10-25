#+vet explicit-allocators
package renderer

import "src:ui"

@(private)
build_notice :: proc(o: ^Overlay, width: f32, notice: ui.Notice) {
	if notice.text == "" {
		return
	}
	ctx: Layout_Context
	layout_context_init(&ctx, o.theme, &o.atlas, width, 0)
	layout := ui.notice_layout(ctx.inputs, notice)
	theme := o.theme

	hud_emit_rect(
		o,
		layout.box.x,
		layout.box.y,
		layout.box.width,
		layout.box.height,
		theme.surface_hud,
	)
	hud_emit_frame(
		o,
		layout.box.x,
		layout.box.y,
		layout.box.width,
		layout.box.height,
		theme.hairline,
		theme.line_hairline,
	)
	text_emit(
		o,
		layout.text_x,
		layout.baseline,
		text_style_for_role(theme, .Body, theme.text_primary),
		notice.text,
	)
}
