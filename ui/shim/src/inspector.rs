use rune::{El, ScrollSpec, TextStyle, col, el, row, spacer};
use rune_kit::{
    Button, ButtonVariant, ControlSize, IconButton, IconButtonVariant, Kit, SegmentedControl, Switch,
};

use crate::abi::{
    ACTION_LAMP_COLOR, ACTION_LAMP_KIND, ACTION_LAMP_SET, ACTION_OBJECT_DELETE,
    ACTION_OBJECT_DUPLICATE, ACTION_OBJECT_SET, ACTION_PHYSICS_DEBUG, ACTION_TOGGLE_INSPECTOR,
    ACTION_TYPE_WEIGHT_SET, LAMP_FIELD_INTENSITY, LAMP_FIELD_RANGE, OBJECT_FIELD_BODY,
    OBJECT_FIELD_YAW, UiAction,
};
use crate::components;
use crate::slider::{self, SliderCommit};
use crate::state::UiState;
use crate::text;

const WIDTH: f32 = 320.0;
const INSET: f32 = 12.0;
const CONTENT_WIDTH: f32 = WIDTH - 24.0;
const BOTTOM_RESERVE: f32 = 60.0;
const LABEL_WIDTH: f32 = 76.0;

pub fn view(state: &UiState, height: f32, layers: &mut Vec<El>) {
    if !state.inspector.open || state.menu.open || state.palette.open {
        state.inspector_scroll.set(0.0);
        state.inspector_scroll_max.set(0.0);
        return;
    }
    let kit = &state.kit;
    let max_height = (height - INSET * 2.0 - BOTTOM_RESERVE).max(240.0);
    let body = col()
        .w_full()
        .gap(4.0)
        .child(object_section(state))
        .child(placement_section(state))
        .child(lamp_section(state))
        .child(debug_section(state));
    let scroll = state.inspector_scroll.clone();
    let scroll_max = state.inspector_scroll_max.clone();
    let viewport = col()
        .w_full()
        .max_h(max_height)
        .min_h(0.0)
        .scroll(ScrollSpec { stick_bottom: false })
        .key("inspector.scroll")
        .on_scroll_offset(move |at| {
            scroll.set(at.offset[1]);
            scroll_max.set(at.max[1]);
        })
        .child(body);
    let panel = components::hud_panel(kit, 0.96)
        .w(WIDTH)
        .padding(12.0)
        .gap(6.0)
        .border(1.0, kit.c.border_muted)
        .on_press(|_: &mut UiState| {})
        .child(header(state))
        .child(viewport);
    layers.push(
        col()
            .absolute(0.0, 0.0)
            .w_full()
            .h_full()
            .items_end()
            .justify_start()
            .padding(INSET)
            .child(panel),
    );
}

fn header(state: &UiState) -> El {
    let kit = &state.kit;
    row()
        .w_full()
        .h(20.0)
        .items_center()
        .child(
            text::styled(
                "Debug · Inspector",
                TextStyle {
                    size: 13.0,
                    line_height: 18.0,
                    ..kit.ty.ui_medium
                },
            )
            .color(kit.c.text_base),
        )
        .child(spacer())
        .child(
            IconButton::new(kit.glyph.close)
                .variant(IconButtonVariant::Ghost)
                .control_size(ControlSize::Small)
                .label("Close inspector")
                .on_press(close)
                .build(kit)
                .key("inspector.close"),
        )
}

fn object_section(state: &UiState) -> El {
    let kit = &state.kit;
    let inspector = &state.inspector;
    let heading = row()
        .w_full()
        .h(18.0)
        .items_center()
        .child(section(kit, "Object"))
        .child(spacer())
        .child(text::styled(&inspector.selection, kit.ty.small).color(kit.c.text_muted));
    if !inspector.has_selection {
        return col()
            .w_full()
            .gap(4.0)
            .child(heading)
            .child(
                text::styled("No object selected", kit.ty.small).color(kit.c.text_muted),
            );
    }
    let body = if inspector.has_lamp {
        value_row(
            kit,
            "Body",
            if inspector.body == 0 {
                "static · follows kind"
            } else {
                "dynamic · follows kind"
            },
        )
    } else {
        SegmentedControl::new(&["Static", "Dynamic"], Some(inspector.body.min(1)))
            .label("Body")
            .width(Some(CONTENT_WIDTH))
            .on_pick(|state: &mut UiState, index, _| {
                state.actions.push(UiAction {
                    kind: ACTION_OBJECT_SET,
                    id: state.inspector.object_id,
                    value: OBJECT_FIELD_BODY as i32,
                    scalar: index as f32,
                });
            })
            .build(kit)
            .key("inspector.body")
    };
    let yaw = inspector_slider(
        state,
        "inspector.yaw",
        "Yaw",
        &inspector.yaw_text,
        inspector.yaw_degrees,
        PreviewField::Yaw,
        SliderAction::ObjectYaw,
        0.0,
        359.0,
        1.0,
    );
    let actions = row()
        .w_full()
        .gap(6.0)
        .child(
            Button::new("Duplicate")
                .control_size(ControlSize::Small)
                .on_press(|state: &mut UiState| {
                    state.actions.push(UiAction {
                        kind: ACTION_OBJECT_DUPLICATE,
                        id: state.inspector.object_id,
                        value: 0,
                        scalar: 0.0,
                    });
                })
                .build(kit)
                .key("inspector.duplicate"),
        )
        .child(
            Button::new("Delete")
                .variant(ButtonVariant::Outline)
                .control_size(ControlSize::Small)
                .on_press(|state: &mut UiState| {
                    state.actions.push(UiAction {
                        kind: ACTION_OBJECT_DELETE,
                        id: state.inspector.object_id,
                        value: 0,
                        scalar: 0.0,
                    });
                })
                .build(kit)
                .key("inspector.delete"),
        )
        .child(spacer());
    col()
        .w_full()
        .gap(4.0)
        .child(heading)
        .child(body)
        .child(yaw)
        .child(actions)
}

fn placement_section(state: &UiState) -> El {
    let kit = &state.kit;
    let inspector = &state.inspector;
    col()
        .w_full()
        .gap(4.0)
        .child(section(kit, "Placement"))
        .child(value_row(kit, "Next prefab", &inspector.placement_prefab))
        .child(
            text::styled(&inspector.placement_text, kit.ty.mono).color(kit.c.text_muted),
        )
}

fn lamp_section(state: &UiState) -> El {
    let kit = &state.kit;
    let inspector = &state.inspector;
    if !inspector.has_lamp {
        return col();
    }
    let kind = SegmentedControl::new(
        &["Static fixture", "Dynamic lamp"],
        Some(if inspector.lamp_kind == 1 { 0 } else { 1 }),
    )
    .label("Lamp kind")
    .width(Some(CONTENT_WIDTH))
    .on_pick(|state: &mut UiState, index, _| {
        state.actions.push(UiAction {
            kind: ACTION_LAMP_KIND,
            id: state.inspector.object_id,
            value: if index == 0 { 1 } else { 0 },
            scalar: 0.0,
        });
    })
    .build(kit)
    .key("inspector.kind");
    let mut swatches = row().w_full().gap(6.0).items_center().child(
        text::styled("Colour", kit.ty.ui)
            .color(kit.c.text_muted)
            .w(LABEL_WIDTH),
    );
    for (index, color) in inspector.lamp_colors.iter().enumerate() {
        let selected = index == inspector.lamp_color;
        let mut swatch = el()
            .size(20.0, 20.0)
            .radius(kit.radius.xs)
            .fill(rune::Color {
                r: color[0],
                g: color[1],
                b: color[2],
                a: color[3],
            })
            .key(format!("inspector.color:{index}"))
            .role("button")
            .label(format!("Colour {}", index + 1))
            .focusable(true)
            .focus_ring(2.0, 1.0, kit.c.border_focus)
            .on_press(move |state: &mut UiState| {
                state.actions.push(UiAction {
                    kind: ACTION_LAMP_COLOR,
                    id: state.inspector.object_id,
                    value: index as i32,
                    scalar: 0.0,
                });
            });
        if selected {
            swatch = swatch.border(1.0, kit.c.border_focus);
        }
        swatches = swatches.child(swatch);
    }
    let intensity = inspector_slider(
        state,
        "inspector.intensity",
        "Intensity",
        &inspector.lamp_intensity_text,
        inspector.lamp_intensity,
        PreviewField::Intensity,
        SliderAction::LampIntensity,
        0.2,
        4.0,
        0.1,
    );
    let range = inspector_slider(
        state,
        "inspector.range",
        "Range",
        &inspector.lamp_range_text,
        inspector.lamp_range,
        PreviewField::Range,
        SliderAction::LampRange,
        2.0,
        20.0,
        1.0,
    );
    col()
        .w_full()
        .gap(4.0)
        .child(section(kit, "Lamp"))
        .child(kind)
        .child(swatches)
        .child(intensity)
        .child(range)
}

fn debug_section(state: &UiState) -> El {
    let kit = &state.kit;
    let inspector = &state.inspector;
    let weight = inspector_slider(
        state,
        "inspector.weight",
        "Type weight",
        &inspector.type_weight_text,
        inspector.type_weight,
        PreviewField::Weight,
        SliderAction::TypeWeight,
        100.0,
        900.0,
        25.0,
    );
    let physics = row()
        .w_full()
        .h(20.0)
        .items_center()
        .child(text::styled("Physics debug", kit.ty.ui).color(kit.c.text_muted))
        .child(spacer())
        .child(
            Switch::new(state.inspector.physics_debug)
                .label("Physics debug")
                .hide_label()
                .on_toggle(|state: &mut UiState| {
                    let next = !state.inspector.physics_debug;
                    state.actions.push(UiAction {
                        kind: ACTION_PHYSICS_DEBUG,
                        id: 0,
                        value: if next { 1 } else { 0 },
                        scalar: 0.0,
                    });
                })
                .build(kit)
                .key("inspector.physics"),
        );
    col()
        .w_full()
        .gap(4.0)
        .child(section(kit, "Debug"))
        .child(weight)
        .child(physics)
}

fn close(state: &mut UiState) {
    state.actions.push(UiAction::new(ACTION_TOGGLE_INSPECTOR));
}

fn section(kit: &Kit, label: &str) -> El {
    text::styled(
        &label.to_uppercase(),
        TextStyle {
            line_height: 16.0,
            tracking: 0.44,
            ..kit.ty.small_medium
        },
    )
    .color(kit.c.text_faint)
}

fn value_row(kit: &Kit, label: &str, value: &str) -> El {
    row()
        .w_full()
        .child(text::styled(label, kit.ty.ui).color(kit.c.text_muted))
        .child(spacer())
        .child(text::styled(value, kit.ty.mono).color(kit.c.text_base))
}

#[derive(Clone, Copy)]
enum PreviewField {
    Yaw,
    Intensity,
    Range,
    Weight,
}

#[derive(Clone, Copy)]
enum SliderAction {
    ObjectYaw,
    LampIntensity,
    LampRange,
    TypeWeight,
}

fn inspector_slider(
    state: &UiState,
    key: &str,
    label: &str,
    value_text: &str,
    value: f32,
    field: PreviewField,
    action: SliderAction,
    min: f32,
    max: f32,
    step: f32,
) -> El {
    slider::slider(
        &state.kit,
        key,
        label,
        value_text,
        true,
        preview_value(state, field).unwrap_or(value),
        min,
        max,
        step,
        CONTENT_WIDTH,
        move |state: &UiState| preview_value(state, field).unwrap_or(value),
        move |state: &mut UiState, next| set_preview(state, field, next),
        move |state: &mut UiState, next| {
            let action = slider_action(action, state, next);
            state.actions.push(action);
        },
        SliderCommit::OnRelease,
    )
}

fn preview_value(state: &UiState, field: PreviewField) -> Option<f32> {
    match field {
        PreviewField::Yaw => state.inspector_preview.yaw,
        PreviewField::Intensity => state.inspector_preview.intensity,
        PreviewField::Range => state.inspector_preview.range,
        PreviewField::Weight => state.inspector_preview.weight,
    }
}

fn set_preview(state: &mut UiState, field: PreviewField, next: f32) {
    match field {
        PreviewField::Yaw => state.inspector_preview.yaw = Some(next),
        PreviewField::Intensity => state.inspector_preview.intensity = Some(next),
        PreviewField::Range => state.inspector_preview.range = Some(next),
        PreviewField::Weight => state.inspector_preview.weight = Some(next),
    }
}

fn slider_action(kind: SliderAction, state: &UiState, next: f32) -> UiAction {
    match kind {
        SliderAction::ObjectYaw => UiAction {
            kind: ACTION_OBJECT_SET,
            id: state.inspector.object_id,
            value: OBJECT_FIELD_YAW as i32,
            scalar: next,
        },
        SliderAction::LampIntensity => UiAction {
            kind: ACTION_LAMP_SET,
            id: state.inspector.object_id,
            value: LAMP_FIELD_INTENSITY as i32,
            scalar: next,
        },
        SliderAction::LampRange => UiAction {
            kind: ACTION_LAMP_SET,
            id: state.inspector.object_id,
            value: LAMP_FIELD_RANGE as i32,
            scalar: next,
        },
        SliderAction::TypeWeight => UiAction {
            kind: ACTION_TYPE_WEIGHT_SET,
            id: 0,
            value: 0,
            scalar: next,
        },
    }
}
