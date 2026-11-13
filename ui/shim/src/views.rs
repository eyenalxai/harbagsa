use rune::{Cx, El, col, effect, el, row, spacer};

use crate::abi::{ACTION_CLOSE_MENU, ACTION_TOGGLE_DEBUG, UiAction};
use crate::components;
use crate::palette;
use crate::settings;
use crate::state::{HUD_OPACITY_PROMOTE, UiState};
use crate::text;

const ROW_NUMERIC: u32 = 1;
const ROW_BLOCKED: u32 = 2;
pub fn view(state: &UiState, cx: &mut Cx<UiState>) -> El {
    cx.reduced_motion(state.settings.reduce_motion);
    // Return presses a focused Button and Switch as a web form does; Space
    // already presses any focused control.
    cx.web_focus();
    let mut overlays = Vec::new();
    let base = if state.palette.open {
        palette::view(state)
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
            0..=3 => {
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

    let close = components::action_button(kit, "Close", state.weight, true)
        .key("action:1")
        .on_press(|state: &mut UiState| {
            state.actions.push(UiAction::new(ACTION_CLOSE_MENU));
        });
    let debug = components::action_button(kit, "Debug", state.weight, false)
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
                actions.child(close).child(debug)
            }),
    );
    root
}

