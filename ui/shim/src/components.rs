use rune::{El, col, el};
use rune_kit::Kit;
use crate::theme;

use crate::abi::UiAction;
use crate::state::UiState;
pub fn hud_panel(kit: &Kit, opacity: f32) -> El {
    let panel = col().radius(kit.radius.md).fill(theme::hud_surface(opacity));
    kit.elevate(panel, &kit.elevation.raised)
}

pub fn dialog_panel(kit: &Kit) -> El {
    let panel = col().radius(kit.radius.md).fill(kit.c.layer_01);
    kit.elevate(panel, &kit.elevation.overlay)
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
