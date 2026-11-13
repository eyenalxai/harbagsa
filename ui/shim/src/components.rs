use rune::{Color, El, col, el};
use rune_kit::Kit;
use crate::theme;

use crate::abi::UiAction;
use crate::state::UiState;
use crate::text;
pub fn hud_panel(kit: &Kit, opacity: f32) -> El {
    let panel = col().radius(kit.radius.md).fill(theme::hud_surface(opacity));
    kit.elevate(panel, &kit.elevation.raised)
}

pub fn dialog_panel(kit: &Kit) -> El {
    let panel = col().radius(kit.radius.md).fill(kit.c.layer_01);
    kit.elevate(panel, &kit.elevation.overlay)
}

// Selection is the raised fill and the leading accent bar. Keeping both here
// stops a menu row and a palette card from drifting apart.
pub fn selection(kit: &Kit, selected: bool, bar_height: f32, resting: Color) -> (Color, El) {
    let fill = if selected {
        kit.c.surface_raised
    } else {
        resting
    };
    let bar = el().w(2.0).h(bar_height);
    let bar = if selected {
        bar.fill(kit.c.bg_accent)
    } else {
        bar
    };
    (fill, bar)
}

pub fn action_button(kit: &Kit, label: &str, weight: f32, accent: bool) -> El {
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

pub fn modal(kit: &Kit, panel: El, close_kind: u32) -> El {
    el()
        .w_full()
        .h_full()
        .child(
            el()
                .absolute(0.0, 0.0)
                .w_full()
                .h_full()
                .fill(kit.c.scrim)
                .on_press(move |state: &mut UiState| {
                    state.actions.push(UiAction::new(close_kind));
                }),
        )
        .child(
            el()
                .absolute(0.0, 0.0)
                .w_full()
                .h_full()
                .center()
                .padding(16.0)
                .child(panel),
        )
}

pub fn hairline(kit: &Kit) -> El {
    el().h(1.0).w_full().fill(kit.c.border_muted)
}
