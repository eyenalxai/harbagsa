#+vet explicit-allocators
#+vet !unused-procedures // the renderer and frame tests call this API; the game binary does not
package ui

Notice_Layout :: struct {
	box:      Rect,
	text_x:   f32,
	baseline: f32,
}

// The notice sits on the top-right margin, level with the status panel. It is
// one body line plus md padding, the same anatomy as the capture hint.
notice_layout :: proc(inputs: Layout_Inputs, notice: Notice) -> Notice_Layout {
	if notice.text == "" {
		return {}
	}
	padding := inputs.spacing.md
	width := inputs.metrics.measure(inputs.metrics.ctx, .Body, notice.text) + padding * 2
	height := inputs.metrics.line_height(inputs.metrics.ctx, .Body) + padding * 2
	// The text is bounded by the write path, so the right margin holds at the
	// smallest supported target. The clamp keeps the left edge on screen anyway.
	x := max(inputs.width - inputs.spacing.md - width, inputs.spacing.md)
	return {
		box = {x, inputs.spacing.md, width, height},
		text_x = x + padding,
		baseline = inputs.spacing.md +
			padding +
			inputs.metrics.baseline(inputs.metrics.ctx, .Body),
	}
}
