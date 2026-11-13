use rune::color::hex;
use rune::{Color, TextStyle};
use rune_kit::{Kit, PaletteFocus, PaletteSeed, Type};

pub const DEFAULT_WEIGHT: f32 = 400.0;
const BG: &str = "#0F141A";
const FG: &str = "#EDF2F7";
const ACCENT: &str = "#E6B03B";
const LAYER: &str = "#141A21";
const RAISED: &str = "#26303D";
const MUTED: &str = "#A6B2BF";
const FAINT: &str = "#808C99";
const HAIRLINE: &str = "#59616B";
const BLACK: &str = "#000000";
pub const FX_GLOW_COLOR: u32 = 0x7C5CFF;
pub const FX_GLOW_CORE: u32 = 0xF4F0FF;

fn token(value: &str) -> Color {
    hex(value).expect("theme token is valid hex")
}

/// The game sends 0 before it has a setting; the authored default is 400.
pub fn normalize_weight(weight: f32) -> f32 {
    if weight > 0.0 { weight.clamp(100.0, 900.0) } else { DEFAULT_WEIGHT }
}

pub fn hud_surface(opacity: f32) -> Color {
    token(BG).alpha(opacity.clamp(0.70, 1.0))
}

pub fn kit(weight: f32) -> Kit {
    let accent = token(ACCENT);
    let mut kit = Kit::from_palette_focus(
        PaletteSeed {
            bg: token(BG),
            fg: token(FG),
            accent,
        },
        PaletteFocus::Accent,
    );

    kit.c.layer_01 = token(LAYER);
    kit.c.surface_raised = token(RAISED);
    kit.c.surface_raised_base = kit.c.surface_raised;
    kit.c.bg_button_neutral = kit.c.surface_raised;
    kit.c.text_base = token(FG);
    kit.c.text_muted = token(MUTED);
    kit.c.text_faint = token(FAINT);
    kit.c.border_muted = token(HAIRLINE).alpha(0.25);
    kit.c.scrim = token(BLACK).alpha(0.62);
    kit.c.bg_accent = accent;
    kit.c.text_accent = accent;
    kit.c.icon_accent = accent;
    kit.c.border_focus = accent;
    kit.c.bg_icon_button_contrast = accent;
    kit.c.submit_fg = token(BG);
    kit.c.submit_icon = token(BG);
    kit.c.bg_contrast = accent;
    kit.c.text_contrast = token(BG);
    kit.c.icon_contrast = token(BG);

    apply_weight(&mut kit.ty, weight);
    kit
}

fn apply_weight(ty: &mut Type, weight: f32) {
    let shift = normalize_weight(weight) - DEFAULT_WEIGHT;
    let styles: [&mut TextStyle; 12] = [
        &mut ty.ui,
        &mut ty.ui_medium,
        &mut ty.ui_compact,
        &mut ty.small,
        &mut ty.small_medium,
        &mut ty.body,
        &mut ty.body_medium,
        &mut ty.text_small,
        &mut ty.text_small_medium,
        &mut ty.text_xsmall,
        &mut ty.text_xsmall_medium,
        &mut ty.mono,
    ];
    for style in styles {
        style.weight = (style.weight + shift).clamp(1.0, 1000.0);
    }
}
