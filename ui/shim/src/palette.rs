use rune::{Color, El, LineCap, Shape, TextStyle, canvas, col, el, row, spacer};
use rune_kit::Kit;

use crate::abi::{ACTION_PALETTE_CLOSE, ACTION_PALETTE_PICK, ACTION_PALETTE_SELECT, UiAction};
use crate::components;
use crate::state::{PaletteItem, PaletteState, UiState};

const WIDTH: f32 = 640.0;
const CARD_W: f32 = 120.0;
const CARD_H: f32 = 92.0;
const GRID_GAP: f32 = 8.0;
const GRID_H: f32 = CARD_H * 4.0 + GRID_GAP * 3.0;
const PREVIEW_W: f32 = 220.0;
const PREVIEW_ART_H: f32 = 168.0;
const ISO_X: f32 = 0.866_025_4;
const ISO_Y: f32 = 0.5;

pub fn view(state: &UiState) -> El {
    let kit = &state.kit;
    let palette = &state.palette;
    let grid_w = CARD_W * 3.0 + GRID_GAP * 2.0;

    let mut grid = col().w(grid_w).equal_columns(3).gap(GRID_GAP);
    for (index, item) in palette.items.iter().enumerate() {
        grid = grid.child(card(kit, item, index, index == palette.selected));
    }

    let count = palette.items.len();
    let count_text = if count == 1 {
        "1 prefab".to_string()
    } else {
        format!("{count} prefabs")
    };
    let title_style = TextStyle {
        size: 18.0,
        line_height: 24.0,
        ..kit.ty.ui_medium
    };

    let mut hints = row().gap(12.0);
    for (keys, action) in &palette.hints {
        hints = hints.child(
            row()
                .gap(4.0)
                .child(text(keys, kit.ty.small_medium, kit.c.text_base))
                .child(text(action, kit.ty.small, kit.c.text_muted)),
        );
    }

    let place = components::action_button(kit, "Place", state.weight, true)
        .key("palette:place")
        .default_button()
        .on_press(|state: &mut UiState| {
            state.actions.push(UiAction::new(ACTION_PALETTE_PICK));
        });

    let panel = components::dialog_panel(kit)
        .w(WIDTH)
        .padding(16.0)
        .gap(12.0)
        .on_press(|_: &mut UiState| {})
        .child(
            row()
                .w_full()
                .items_center()
                .child(text(&palette.title, title_style, kit.c.text_base))
                .child(spacer())
                .child(text(&count_text, kit.ty.small, kit.c.text_faint)),
        )
        .child(components::hairline(kit))
        .child(
            row()
                .w_full()
                .gap(12.0)
                .child(grid)
                .child(preview(kit, palette)),
        )
        .child(
            row()
                .w_full()
                .items_center()
                .gap(12.0)
                .child(hints)
                .child(spacer())
                .child(place),
        );

    components::modal(kit, panel, ACTION_PALETTE_CLOSE)
}

fn card(kit: &Kit, item: &PaletteItem, index: usize, selected: bool) -> El {
    let fill = if selected {
        kit.c.surface_raised
    } else {
        kit.c.layer_02
    };
    let short = if selected {
        kit.c.text_base
    } else {
        kit.c.text_muted
    };
    // The second line is a card label, so it stays at the 4.5:1 text floor on
    // both the resting and the raised surface.
    let name = kit.c.text_muted;
    let bar = if selected {
        el().w(2.0).h_full().fill(kit.c.bg_accent)
    } else {
        el().w(2.0).h_full()
    };
    let badge = if item.key.is_empty() {
        el().size(16.0, 16.0)
    } else {
        el()
            .size(16.0, 16.0)
            .radius(kit.radius.xs)
            .fill(kit.c.layer_01)
            .center()
            .child(text(&item.key, kit.ty.small_medium, kit.c.text_muted))
    };
    let content = col()
        .grow(1.0)
        .padding(10.0)
        .gap(4.0)
        .child(
            row()
                .w_full()
                .items_center()
                .child(
                    el()
                        .size(32.0, 24.0)
                        .radius(kit.radius.xs)
                        .fill(item_color(item)),
                )
                .child(spacer())
                .child(badge),
        )
        .child(text(&item.short, kit.ty.ui_medium, short))
        .child(text(&item.name, kit.ty.small, name));

    row()
        .size(CARD_W, CARD_H)
        .radius(kit.radius.md)
        .fill(fill)
        .child(bar)
        .child(content)
        .key(format!("palette:{index}"))
        .role("button")
        .label(format!("{} — {}", item.short, item.name))
        .focusable(true)
        .focus_within_ring(2.0, 1.0, kit.c.border_focus)
        .hover(kit.c.hover)
        .press(kit.c.pressed)
        .on_press(move |state: &mut UiState| {
            state
                .actions
                .push(UiAction::with_value(ACTION_PALETTE_SELECT, index as i32));
        })
}

fn preview(kit: &Kit, palette: &PaletteState) -> El {
    let panel = col()
        .w(PREVIEW_W)
        .h(GRID_H)
        .radius(kit.radius.md)
        .fill(kit.c.layer_02)
        .padding(12.0)
        .gap(8.0)
        .child(text("Preview", kit.ty.small_medium, kit.c.text_faint));

    let Some(item) = palette.items.get(palette.selected) else {
        return panel.child(text("No prefab", kit.ty.small, kit.c.text_muted));
    };

    let body = if palette.body.is_empty() {
        item.body.as_str()
    } else {
        palette.body.as_str()
    };
    let light = if item.emissive && !item.light_line.is_empty() {
        item.light_line.as_str()
    } else {
        "No light"
    };
    let size = format!(
        "{:.1} × {:.1} × {:.1} m",
        item.half_extents[0] * 2.0,
        item.half_extents[1] * 2.0,
        item.half_extents[2] * 2.0,
    );

    panel
        .child(
            row()
                .w_full()
                .items_center()
                .gap(8.0)
                .child(
                    el()
                        .size(24.0, 18.0)
                        .radius(kit.radius.xs)
                        .fill(item_color(item)),
                )
                .child(text(&item.name, kit.ty.ui_medium, kit.c.text_base))
                .child(spacer())
                .child(text(&item.key, kit.ty.small_medium, kit.c.text_faint)),
        )
        .child(canvas(iso_shape(kit, item)).size(PREVIEW_W - 24.0, PREVIEW_ART_H))
        .child(spacer())
        .child(value_row(kit, "Size", &size, true))
        .child(value_row(kit, "Body", body, false))
        .child(text("Light", kit.ty.small, kit.c.text_faint))
        .child(text(light, kit.ty.small, kit.c.text_muted))
}

fn value_row(kit: &Kit, label: &str, value: &str, mono: bool) -> El {
    let style = if mono { kit.ty.mono } else { kit.ty.small };
    row()
        .w_full()
        .child(text(label, kit.ty.small, kit.c.text_faint))
        .child(spacer())
        .child(text(value, style, kit.c.text_muted))
}

fn text(content: &str, style: TextStyle, color: Color) -> El {
    rune::text(content).font(style).color(color)
}

fn item_color(item: &PaletteItem) -> Color {
    Color {
        r: item.color[0],
        g: item.color[1],
        b: item.color[2],
        a: item.color[3],
    }
}

fn iso_shape(kit: &Kit, item: &PaletteItem) -> Shape {
    let hx = item.half_extents[0].max(0.05);
    let hy = item.half_extents[1].max(0.05);
    let hz = item.half_extents[2].max(0.05);
    let top = hy * 2.0;
    let project = |point: [f32; 3]| {
        [
            (point[0] - point[2]) * ISO_X,
            (point[0] + point[2]) * ISO_Y - point[1],
        ]
    };
    let points = [
        [-hx, 0.0, -hz],
        [hx, 0.0, -hz],
        [hx, top, -hz],
        [-hx, top, -hz],
        [-hx, 0.0, hz],
        [hx, 0.0, hz],
        [hx, top, hz],
        [-hx, top, hz],
    ];
    let projected = points.map(project);
    let min_x = projected.iter().map(|p| p[0]).fold(f32::INFINITY, f32::min);
    let max_x = projected.iter().map(|p| p[0]).fold(f32::NEG_INFINITY, f32::max);
    let min_y = projected.iter().map(|p| p[1]).fold(f32::INFINITY, f32::min);
    let max_y = projected.iter().map(|p| p[1]).fold(f32::NEG_INFINITY, f32::max);
    let art_w = PREVIEW_W - 24.0;
    let scale = ((art_w / (max_x - min_x)).min(PREVIEW_ART_H / (max_y - min_y))).max(0.01);
    let offset_x = (art_w - (max_x - min_x) * scale) * 0.5 - min_x * scale;
    let offset_y = (PREVIEW_ART_H - (max_y - min_y) * scale) * 0.5 - min_y * scale;
    let place = |index: usize| {
        [
            projected[index][0] * scale + offset_x,
            projected[index][1] * scale + offset_y,
        ]
    };

    let color = item_color(item);
    let edge = kit.c.layer_01.alpha(0.8);
    let top_face = vec![place(3), place(7), place(6), place(2)];
    let right_face = vec![place(1), place(5), place(6), place(2)];
    let front_face = vec![place(4), place(5), place(6), place(7)];
    Shape::new()
        .fill(top_face.clone(), color.mix(kit.c.white, 0.22))
        .fill(right_face.clone(), color.mix(kit.c.black, 0.10))
        .fill(front_face.clone(), color.mix(kit.c.black, 0.24))
        .stroke_with(top_face, true, 1.0, LineCap::Round, edge)
        .stroke_with(right_face, true, 1.0, LineCap::Round, edge)
        .stroke_with(front_face, true, 1.0, LineCap::Round, edge)
}
