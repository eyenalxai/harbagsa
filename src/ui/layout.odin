#+vet !unused-procedures // the renderer and frame tests call this API; the game binary does not
package ui

import "core:math"

HUD_MENU_MAX_HINT_COLUMNS :: 8
HINT_COLUMNS :: 3

Spacing :: struct {
	xxs: f32,
	xs:  f32,
	sm:  f32,
	md:  f32,
	lg:  f32,
	xl:  f32,
	xxl: f32,
}

Rect :: struct {
	x:      f32,
	y:      f32,
	width:  f32,
	height: f32,
}

Text_Role :: enum {
	Title,
	Body,
	Body_Strong,
	Caption,
	Caption_Caps,
	Mono_Body,
	Mono_Caption,
}

// Layout asks for a role and a string. The renderer maps the role to a font,
// weight, and colour; tests use a fake measure and need no atlas.
Text_Metrics :: struct {
	ctx:         rawptr,
	measure:     proc(ctx: rawptr, role: Text_Role, text: string) -> f32,
	line_height: proc(ctx: rawptr, role: Text_Role) -> f32,
	baseline:    proc(ctx: rawptr, role: Text_Role) -> f32,
}

Layout_Inputs :: struct {
	width:          f32,
	height:         f32,
	spacing:        Spacing,
	hairline:       f32,
	density:        f32,
	menu_min_width: f32,
	metrics:        Text_Metrics,
}

Rows_Options :: struct {
	value_align: Row_Align,
	frame_x:     f32,
	frame_width: f32,
	selected:    int,
}

Rows_Layout :: struct {
	width:        f32,
	height:       f32,
	label_column: f32,
	value_column: f32,
	value_width:  f32,
}

Hint_Grid :: struct {
	width:      f32,
	height:     f32,
	columns:    int,
	rows:       int,
	column_x:   [HUD_MENU_MAX_HINT_COLUMNS]f32,
	key_width:  [HUD_MENU_MAX_HINT_COLUMNS]f32,
	row_height: f32,
}

row_label_role :: proc(kind: Row_Kind) -> Text_Role {
	switch kind {
	case .Setting, .Action, .Slider:
		return .Body_Strong
	case .Metric:
		return .Body
	case .Detail:
		return .Caption
	case .Header:
		return .Caption_Caps
	case .Divider:
	}
	return .Body
}

row_value_role :: proc(row: Row) -> Text_Role {
	role: Text_Role = .Body
	if row.kind == .Detail {
		role = .Caption
	}
	if row.numeric {
		if row.kind == .Detail {
			return .Mono_Caption
		}
		return .Mono_Body
	}
	return role
}

row_gap :: proc(inputs: Layout_Inputs, kind: Row_Kind) -> f32 {
	switch kind {
	case .Header:
		return inputs.spacing.lg
	case .Divider, .Setting, .Action, .Slider:
		return inputs.spacing.sm
	case .Metric, .Detail:
	}
	return inputs.spacing.xs
}

row_height :: proc(inputs: Layout_Inputs, kind: Row_Kind) -> f32 {
	switch kind {
	case .Header, .Detail:
		return inputs.metrics.line_height(inputs.metrics.ctx, .Caption)
	case .Divider:
		return inputs.hairline
	case .Slider:
		return inputs.metrics.line_height(inputs.metrics.ctx, .Body) +
			inputs.spacing.sm +
			inputs.spacing.lg
	case .Setting, .Action, .Metric:
	}
	return inputs.metrics.line_height(inputs.metrics.ctx, .Body)
}

rows_layout :: proc(inputs: Layout_Inputs, rows: []Row, options: Rows_Options) -> Rows_Layout {
	layout: Rows_Layout
	for row, index in rows {
		if index > 0 {
			layout.height += row_gap(inputs, row.kind)
		}
		layout.height += row_height(inputs, row.kind)
		switch row.kind {
		case .Header, .Divider:
		case .Setting, .Action, .Metric, .Detail, .Slider:
			if row.label != "" {
				layout.label_column = max(
					layout.label_column,
					inputs.metrics.measure(
						inputs.metrics.ctx,
						row_label_role(row.kind),
						row.label,
					),
				)
			}
			if row.value != "" {
				layout.value_width = max(
					layout.value_width,
					inputs.metrics.measure(inputs.metrics.ctx, row_value_role(row), row.value),
				)
			}
		}
	}
	layout.value_column = layout.label_column + inputs.spacing.xl
	layout.width = layout.value_column + layout.value_width
	return layout
}

// The row offset comes from the same walk that draws the rows, so a control
// that the caller measures outside the draw lands on its drawn row.
rows_row_y :: proc(inputs: Layout_Inputs, rows: []Row, index: int) -> f32 {
	offset: f32
	for row, current in rows {
		if current > index {
			break
		}
		if current > 0 {
			offset += row_gap(inputs, row.kind)
		}
		if current == index {
			break
		}
		offset += row_height(inputs, row.kind)
	}
	return offset
}

slider_center_y :: proc(inputs: Layout_Inputs, row_y: f32) -> f32 {
	return row_y +
		inputs.metrics.line_height(inputs.metrics.ctx, .Body) +
		inputs.spacing.sm +
		inputs.spacing.lg * 0.5
}

slider_rect :: proc(
	inputs: Layout_Inputs,
	frame_x, frame_width, row_y: f32,
) -> Slider_Rect {
	center_y := slider_center_y(inputs, row_y)
	return {
		x      = frame_x,
		y      = snap(center_y - inputs.spacing.lg * 0.5),
		width  = frame_width,
		height = inputs.spacing.lg,
		knob   = inputs.spacing.md,
	}
}

snap :: proc(value: f32) -> f32 {
	return math.round(value)
}

hint_grid :: proc(inputs: Layout_Inputs, menu: Menu) -> Hint_Grid {
	grid: Hint_Grid
	columns := menu.hint_columns
	if columns <= 0 {
		columns = HINT_COLUMNS
	}
	grid.columns = clamp(columns, 1, HUD_MENU_MAX_HINT_COLUMNS)
	if len(menu.hints) == 0 {
		return grid
	}
	grid.rows = (len(menu.hints) + grid.columns - 1) / grid.columns
	grid.row_height =
		inputs.metrics.line_height(inputs.metrics.ctx, .Caption) + inputs.spacing.xxs

	action_width: [HUD_MENU_MAX_HINT_COLUMNS]f32
	for cell, index in menu.hints {
		if cell.keys == "" {
			continue
		}
		column := index % grid.columns
		grid.key_width[column] = max(
			grid.key_width[column],
			inputs.metrics.measure(inputs.metrics.ctx, .Caption_Caps, cell.keys),
		)
		action_width[column] = max(
			action_width[column],
			inputs.metrics.measure(inputs.metrics.ctx, .Caption, cell.action),
		)
	}

	offset: f32
	for column in 0 ..< grid.columns {
		grid.column_x[column] = offset
		offset += grid.key_width[column] + inputs.spacing.xs + action_width[column]
		if column < grid.columns - 1 {
			offset += inputs.spacing.xl
		}
	}
	grid.width = offset
	grid.height = f32(grid.rows) * grid.row_height
	return grid
}

// The pointer arrives normalized to the window; layout and hit tests work in
// target pixels. This is the one place that rescales it.
pointer_to_target :: proc(pointer: [2]f32, width, height: f32) -> [2]f32 {
	return {pointer.x * width, pointer.y * height}
}
