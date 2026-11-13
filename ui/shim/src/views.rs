use rune::{Cx, Color, El, col, effect, el, row, spacer};
use rune_kit::Kit;

use crate::abi::{
    ACTION_OPEN_MENU, ACTION_PALETTE_CLOSE, ACTION_PALETTE_SELECT, ACTION_TOGGLE_DEBUG, UiAction,
};
use crate::components;
use crate::settings;
use crate::state::{HUD_OPACITY_PROMOTE, MenuPanel, PanelRow, UiState};
use crate::text;

const ROW_NUMERIC: u32 = 1;
const ROW_BLOCKED: u32 = 2;
const MENU_WIDTH: f32 = 430.0;

pub fn view(state: &UiState, cx: &mut Cx<UiState>) -> El {
    cx.reduced_motion(state.settings.reduce_motion);
    // Return presses a focused Button and Switch as a web form does; Space
    // already presses any focused control.
    cx.web_focus();
    let mut overlays = Vec::new();
    let base = if state.palette.open {
        palette_view(state)
    } else {
        hud_view(state)
    };
    settings::dialog(state, &mut overlays);
    rune_kit::root(base, overlays)
}

fn hud_view(state: &UiState) -> El {
    let kit = &state.kit;
    let opacity = state.settings.hud_opacity;
    let tertiary = if opacity < HUD_OPACITY_PROMOTE {
        kit.c.text_muted
    } else {
        kit.c.text_faint
    };
    let mut panel = components::hud_panel(kit, opacity)
        .w(380.0)
        .padding(12.0)
        .gap(6.0);
    for entry in &state.panel.rows {
        panel = match entry.kind {
            5 => panel.child(components::hairline(kit)),
            6 => panel.child(text::weighted(&entry.label, state.weight, false).color(tertiary)),
            0..=4 => {
                let label = if entry.kind == 3 { tertiary } else { kit.c.text_muted };
                let value = if entry.flags & ROW_BLOCKED != 0 {
                    kit.c.text_muted
                } else {
                    kit.c.text_base
                };
                panel.child(
                    row()
                        .w_full()
                        .gap(12.0)
                        .child(text::weighted(&entry.label, state.weight, false).color(label))
                        .child(spacer())
                        .child(
                            text::weighted(&entry.value, state.weight, entry.flags & ROW_NUMERIC != 0)
                                .color(value),
                        ),
                )
            }
            _ => panel,
        };
    }

    let mut root = col().w_full().h_full().child(
        el()
            .absolute(0.0, 0.0)
            .w_full()
            .h_full()
            .items_start()
            .justify_start()
            .padding(12.0)
            .child(panel),
    );
    if state.menu_open {
        return root;
    }

    let hint = if state.panel.capture_hint.is_empty()
        || state.panel.captured
        || state.panel.palette_open
    {
        col()
    } else {
        text::weighted(&state.panel.capture_hint, state.weight, false).color(kit.c.text_base)
    };
    let notice = if state.panel.notice.is_empty() {
        col()
    } else {
        text::weighted(&state.panel.notice, state.weight, false).color(kit.c.text_base)
    };

    let settings = button(kit, "Settings", state.weight, true)
        .key("action:settings")
        .on_press(|state: &mut UiState| {
            state.actions.push(UiAction::new(ACTION_OPEN_MENU));
        });
    let debug = button(kit, "Debug", state.weight, false)
        .key("action:2")
        .on_press(|state: &mut UiState| {
            state.actions.push(UiAction::new(ACTION_TOGGLE_DEBUG));
        });

    let glow = effect(crate::fx::GLOW)
        .effect_data([0.9, 0.0, 0.0, 0.0])
        .effect_bleed(60.0)
        .opacity(0.85);
    root = root.child(
        col()
            .w_full()
            .h_full()
            .justify_end()
            .items_center()
            .padding(16.0)
            .gap(8.0)
            .child(notice)
            .child(hint)
            .child({
                let mut actions = row().gap(8.0);
                if state.fx {
                    actions = actions.child(glow.absolute(0.0, 0.0).w_full().h_full());
                }
                actions.child(settings).child(debug)
            }),
    );
    root
}

fn button(kit: &Kit, label: &str, weight: f32, accent: bool) -> El {
    let (fill, ink) = if accent {
        (kit.c.bg_accent, kit.c.text_inverse)
    } else {
        (kit.c.bg_button_neutral, kit.c.text_base)
    };
    let (hover, press) = if accent {
        (kit.c.contrast_hover, kit.c.contrast_pressed)
    } else {
        (kit.c.hover, kit.c.pressed)
    };
    el()
        .padding(8.0)
        .radius(kit.radius.md)
        .focusable(true)
        .focus_ring(2.0, 2.0, kit.c.border_focus)
        .hover(hover)
        .press(press)
        .fill(fill)
        .child(text::weighted(label, weight, false).color(ink))
}

fn palette_view(state: &UiState) -> El {
    let palette = &state.palette;
    let menu = MenuPanel {
        title: palette.title.clone(),
        rows: palette
            .items
            .iter()
            .map(|item| PanelRow {
                kind: 0,
                flags: 0,
                label: item.short.clone(),
                value: item.name.clone(),
                ratio: 0.0,
            })
            .collect(),
        selected: palette.selected,
        note: palette.body.clone(),
        hints: palette.hints.clone(),
    };
    components::modal(
        &state.kit,
        menu_panel(&menu, &state.kit, state.weight, Some("palette:")),
        ACTION_PALETTE_CLOSE,
    )
}

fn menu_panel(menu: &MenuPanel, kit: &Kit, weight: f32, key_prefix: Option<&str>) -> El {
    let mut panel = components::dialog_panel(kit)
        .w(MENU_WIDTH)
        .padding(16.0)
        .gap(8.0)
        .on_press(|_: &mut UiState| {});
    panel = panel
        .child(
            row()
                .w_full()
                .child(spacer())
                .child(text::weighted(&menu.title, weight, false).color(kit.c.text_base))
                .child(spacer()),
        )
        .child(components::hairline(kit));

    for (index, entry) in menu.rows.iter().enumerate() {
        if entry.kind == 5 {
            panel = panel.child(components::hairline(kit));
            continue;
        }
        if entry.kind == 6 {
            panel = panel.child(text::weighted(&entry.label, weight, false).color(kit.c.text_faint));
            continue;
        }
        let selected = index == menu.selected;
        let label = if selected { kit.c.text_base } else { kit.c.text_muted };
        let mut line = row()
            .w_full()
            .padding(4.0)
            .gap(12.0)
            .fill(if selected { kit.c.surface_raised } else { Color::TRANSPARENT })
            .child(if selected {
                el().w(2.0).h(18.0).fill(kit.c.bg_accent)
            } else {
                el()
            })
            .child(text::weighted(&entry.label, weight, false).color(label))
            .child(spacer())
            .child(
                text::weighted(&entry.value, weight, entry.flags & ROW_NUMERIC != 0)
                    .color(kit.c.text_base),
            );
        if let Some(prefix) = key_prefix {
            let index_value = index as i32;
            line = line
                .key(format!("{prefix}{index}"))
                .hover(kit.c.hover)
                .press(kit.c.pressed)
                .on_press(move |state: &mut UiState| {
                    state
                        .actions
                        .push(UiAction::with_value(ACTION_PALETTE_SELECT, index_value));
                });
        }
        panel = panel.child(line);
        if entry.kind == 4 {
            let track = el()
                .w_full()
                .h(4.0)
                .fill(kit.light(0.20))
                .child(el().w_frac(entry.ratio).h_full().fill(kit.c.bg_accent));
            panel = panel.child(track);
        }
    }

    let note = if menu.note.is_empty() {
        col()
    } else {
        text::weighted(&menu.note, weight, false).color(kit.c.text_faint)
    };
    panel = panel.child(note);

    let mut hints = col().w_full().gap(4.0);
    for chunk in menu.hints.chunks(3) {
        let mut line = row().gap(16.0);
        for (keys, action) in chunk {
            line = line
                .child(text::weighted(keys, weight, false).color(kit.c.text_base))
                .child(text::weighted(action, weight, false).color(kit.c.text_muted));
        }
        hints = hints.child(line);
    }
    panel.child(hints)
}
