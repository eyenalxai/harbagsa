#+vet explicit-allocators
package renderer

import "src:ui"

PALETTE_PREVIEW_BOX :: 64.0
PALETTE_PREVIEW_LABELS := [4]string{"Size", "Body", "Light", "Objects"}

build_palette :: proc(o: ^Overlay, width, height: f32, palette: ui.Palette) {
	theme := o.theme
	view := palette
	layout := palette_layout(theme, width, height, view.item_count)

	hud_emit_rect(
		o,
		layout.panel.x,
		layout.panel.y,
		layout.panel.width,
		layout.panel.height,
		theme.surface_hud,
	)
	hud_emit_frame(
		o,
		layout.panel.x,
		layout.panel.y,
		layout.panel.width,
		layout.panel.height,
		theme.hairline,
		theme.line_hairline,
	)

	title_style := Text_Style{type = theme.type_caption_caps, color = theme.text_tertiary}
	text_emit(
		o,
		layout.title.x,
		layout.title.y + text_baseline(&o.atlas, title_style.type),
		title_style,
		view.title,
	)

	count := min(view.item_count, layout.card_count)
	for item, index in view.items[:count] {
		build_palette_card(o, layout.cards[index], item, index == view.selected)
	}
	for index in count ..< PALETTE_SLOTS {
		card := layout.cards[index]
		hud_emit_frame(o, card.x, card.y, card.width, card.height, theme.hairline, theme.line_hairline)
	}

	if view.selected >= 0 && view.selected < count {
		build_palette_preview(o, layout, view.items[view.selected], &view)
	}
	hints := clamp(view.hint_count, 0, len(view.hints))
	build_palette_footer(o, layout, view.hints[:hints])
}

@(private)
build_palette_card :: proc(o: ^Overlay, card: HUD_Rect, item: ui.Palette_Item, selected: bool) {
	theme := o.theme
	fill := theme.surface_menu
	if selected {
		fill = theme.surface_raised
	}
	hud_emit_rect(o, card.x, card.y, card.width, card.height, fill)
	hud_emit_frame(o, card.x, card.y, card.width, card.height, theme.hairline, theme.line_hairline)
	if selected {
		hud_emit_rect(o, card.x, card.y, max(theme.hairline * 2, 2), card.height, theme.accent)
	}

	name_height := theme.type_caption.line_height
	thumbnail := HUD_Rect {
		x      = card.x + theme.spacing.xs,
		y      = card.y + theme.spacing.sm,
		width  = card.width - theme.spacing.xs * 2,
		height = card.height - name_height - theme.spacing.sm - theme.spacing.xs,
	}
	build_palette_iso(o, item, thumbnail)

	key_color := selected ? theme.text_primary : theme.text_secondary
	key_style := Text_Style{type = theme.type_caption_caps, color = key_color}
	if item.key != "" {
		text_emit_aligned(
			o,
			card.x + card.width - theme.spacing.xs,
			card.y + theme.spacing.xs + text_baseline(&o.atlas, key_style.type),
			key_style,
			item.key,
			.Right,
		)
	}

	name_color := selected ? theme.text_primary : theme.text_secondary
	name_style := Text_Style{type = theme.type_caption, color = name_color}
	text_emit(
		o,
		card.x + theme.spacing.xs,
		card.y + card.height - theme.spacing.xs - name_height +
		text_baseline(&o.atlas, name_style.type),
		name_style,
		item.short_name,
	)
}

@(private)
build_palette_iso :: proc(o: ^Overlay, item: ui.Palette_Item, rect: HUD_Rect) {
	box := palette_project_box(item.half_extents, item.base_pitch)
	transform := palette_fit_transform(box, rect)
	for face in box.faces[:box.count] {
		color := [4]f32{
			item.color.r * face.shade,
			item.color.g * face.shade,
			item.color.b * face.shade,
			item.color.a,
		}
		hud_emit_quad(
			o,
			palette_transform_point(transform, face.points[0]),
			palette_transform_point(transform, face.points[1]),
			palette_transform_point(transform, face.points[2]),
			palette_transform_point(transform, face.points[3]),
			color,
		)
	}
}

@(private)
build_palette_preview :: proc(
	o: ^Overlay,
	layout: Palette_Layout,
	item: ui.Palette_Item,
	palette: ^ui.Palette,
) {
	theme := o.theme
	separator_height := layout.footer.y - theme.spacing.xs - layout.preview.y
	hud_emit_rect(
		o,
		layout.preview.x - theme.spacing.lg * 0.5,
		layout.preview.y,
		theme.hairline,
		separator_height,
		theme.line_separator,
	)

	box_height := min(PALETTE_PREVIEW_BOX * theme.density, layout.preview.height * 0.36)
	box_rect := HUD_Rect{layout.preview.x, layout.preview.y, layout.preview.width, box_height}
	build_palette_iso(o, item, box_rect)

	name_style := Text_Style{type = theme.type_body_strong, color = theme.text_primary}
	text_y := box_rect.y + box_rect.height + theme.spacing.xs
	text_emit(
		o,
		layout.preview.x,
		text_y + text_baseline(&o.atlas, name_style.type),
		name_style,
		item.name,
	)
	text_y += name_style.type.line_height

	label_style := Text_Style{type = theme.type_caption, color = theme.text_tertiary}
	value_style := Text_Style{type = theme.type_caption, color = theme.text_secondary}
	label_width: f32
	for label in PALETTE_PREVIEW_LABELS {
		label_width = max(label_width, text_measure(&o.atlas, label_style.type, label))
	}
	value_x := layout.preview.x + label_width + theme.spacing.sm
	baseline := text_y + text_baseline(&o.atlas, label_style.type)
	palette_preview_line(
		o,
		layout.preview.x,
		value_x,
		baseline,
		label_style,
		value_style,
		"Size",
		palette_text(palette.size[:], palette.size_length),
	)
	text_y += label_style.type.line_height
	baseline = text_y + text_baseline(&o.atlas, label_style.type)
	palette_preview_line(
		o,
		layout.preview.x,
		value_x,
		baseline,
		label_style,
		value_style,
		"Body",
		palette.body,
	)
	text_y += label_style.type.line_height
	if item.light_line != "" {
		baseline = text_y + text_baseline(&o.atlas, label_style.type)
		palette_preview_line(
			o,
			layout.preview.x,
			value_x,
			baseline,
			label_style,
			value_style,
			"Light",
			item.light_line,
		)
		text_y += label_style.type.line_height
	}
	baseline = text_y + text_baseline(&o.atlas, label_style.type)
	palette_preview_line(
		o,
		layout.preview.x,
		value_x,
		baseline,
		label_style,
		value_style,
		"Objects",
		palette_text(palette.count[:], palette.count_length),
	)
}

@(private)
palette_text :: proc(buffer: []u8, length: int) -> string {
	return string(buffer[:clamp(length, 0, len(buffer))])
}

@(private)
palette_preview_line :: proc(
	o: ^Overlay,
	label_x, value_x, baseline: f32,
	label_style, value_style: Text_Style,
	label, value: string,
) {
	text_emit(o, label_x, baseline, label_style, label)
	text_emit(o, value_x, baseline, value_style, value)
}

@(private)
build_palette_footer :: proc(o: ^Overlay, layout: Palette_Layout, hints: []ui.Hint_Cell) {
	theme := o.theme
	hud_emit_rect(
		o,
		layout.footer.x,
		layout.footer.y - theme.spacing.xs,
		layout.footer.width,
		theme.hairline,
		theme.line_separator,
	)

	key_style := Text_Style{type = theme.type_caption_caps, color = theme.text_secondary}
	action_style := Text_Style{type = theme.type_caption, color = theme.text_tertiary}
	baseline := layout.footer.y + text_baseline(&o.atlas, key_style.type)
	x := layout.footer.x
	for hint in hints {
		if hint.keys == "" {
			continue
		}
		text_emit(o, x, baseline, key_style, hint.keys)
		x += text_measure(&o.atlas, key_style.type, hint.keys) + theme.spacing.xs
		text_emit(o, x, baseline, action_style, hint.action)
		x += text_measure(&o.atlas, action_style.type, hint.action) + theme.spacing.xl
	}
}
