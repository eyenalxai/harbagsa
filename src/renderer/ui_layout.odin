#+vet explicit-allocators
#+vet !unused-procedures // the frame tests read the layout aliases
package renderer

import "src:ui"

HUD_Rect :: ui.Rect
Rows_Layout :: ui.Rows_Layout

Layout_Context :: struct {
	theme:  UI_Theme,
	atlas:  ^Text_Atlas,
	inputs: ui.Layout_Inputs,
}

// The metrics adapter lives on the caller's stack. It is passed into one layout
// call and never stored, so a draw and an input pass can each own their result.
layout_context_init :: proc(
	ctx: ^Layout_Context,
	theme: UI_Theme,
	atlas: ^Text_Atlas,
	width, height: f32,
) {
	ctx.theme = theme
	ctx.atlas = atlas
	ctx.inputs = {
		width = width,
		height = height,
		spacing = theme.spacing,
		hairline = theme.hairline,
		density = theme.density,
		menu_min_width = theme.menu_min_width,
		metrics = {
			ctx = ctx,
			measure = layout_measure,
			line_height = layout_line_height,
			baseline = layout_baseline,
		},
	}
}

text_type_for_role :: proc(theme: UI_Theme, role: ui.Text_Role) -> Text_Type {
	switch role {
	case .Title:
		return theme.type_title
	case .Body:
		return theme.type_body
	case .Body_Strong:
		return theme.type_body_strong
	case .Caption:
		return theme.type_caption
	case .Caption_Caps:
		return theme.type_caption_caps
	case .Mono_Body:
		type := theme.type_body
		type.face = .Mono
		type.weight = min(type.weight, MONO_MAX_WEIGHT)
		return type
	case .Mono_Caption:
		type := theme.type_caption
		type.face = .Mono
		type.weight = min(type.weight, MONO_MAX_WEIGHT)
		return type
	}
	return theme.type_body
}

text_style_for_role :: proc(theme: UI_Theme, role: ui.Text_Role, color: [4]f32) -> Text_Style {
	return {type = text_type_for_role(theme, role), color = color}
}

menu_layout_for :: proc(r: ^Renderer, menu: ui.Menu) -> ui.Menu_Layout {
	width, height := target_extent(r)
	ctx: Layout_Context
	layout_context_init(
		&ctx,
		r.overlay.theme,
		&r.overlay.atlas,
		f32(width),
		f32(height),
	)
	return ui.menu_layout(ctx.inputs, menu)
}

@(private)
layout_measure :: proc(ctx: rawptr, role: ui.Text_Role, text: string) -> f32 {
	layout := cast(^Layout_Context)ctx
	return text_measure(layout.atlas, text_type_for_role(layout.theme, role), text)
}

@(private)
layout_line_height :: proc(ctx: rawptr, role: ui.Text_Role) -> f32 {
	layout := cast(^Layout_Context)ctx
	return text_type_for_role(layout.theme, role).line_height
}

@(private)
layout_baseline :: proc(ctx: rawptr, role: ui.Text_Role) -> f32 {
	layout := cast(^Layout_Context)ctx
	return text_baseline(layout.atlas, text_type_for_role(layout.theme, role))
}
