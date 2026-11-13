use rune_kit::Kit;

use crate::abi::{
    self, UiAction, UiEvent, UiMenu, UiPalette, UiPanel, UiSnapshot,
};
use crate::{host::Host, input, theme};

#[derive(Default)]
pub struct PanelRow {
    pub kind: u32,
    pub flags: u32,
    pub label: String,
    pub value: String,
    pub ratio: f32,
}

#[derive(Default)]
pub struct MenuState {
    pub open: bool,
    pub title: String,
    pub rows: Vec<PanelRow>,
    pub selected: usize,
    pub note: String,
    pub hints: Vec<(String, String)>,
}

/// The palette payload travels whole; the grid and preview read the extra
/// fields when their ticket lands.
#[allow(dead_code)]
/// The full palette payload lands with this ticket; the grid and preview
/// tickets read the extra fields.
#[allow(dead_code)]
pub struct PaletteItem {
    pub name: String,
    pub short: String,
    pub half_extents: [f32; 3],
    pub color: [f32; 4],
    pub base_pitch: f32,
    pub body: String,
    pub key: String,
    pub light_line: String,
    pub emissive: bool,
}

#[allow(dead_code)]
#[derive(Default)]
#[allow(dead_code)]
pub struct PaletteState {
    pub open: bool,
    pub title: String,
    pub items: Vec<PaletteItem>,
    pub selected: usize,
    pub body: String,
    pub size: String,
    pub count: String,
    pub hints: Vec<(String, String)>,
}

#[derive(Default)]
pub struct PanelState {
    pub rows: Vec<PanelRow>,
    pub notice: String,
    pub capture_hint: String,
    pub captured: bool,
    pub palette_open: bool,
}

pub struct UiState {
    pub speed: f32,
    pub grounded: bool,
    pub menu_open: bool,
    pub fx: bool,
    pub weight: f32,
    pub kit: Kit,
    pub actions: Vec<UiAction>,
    pub panel: PanelState,
    pub menu: MenuState,
    pub palette: PaletteState,
}

impl UiState {
    pub fn new() -> Self {
        Self {
            speed: 0.0,
            grounded: false,
            menu_open: false,
            fx: false,
            weight: theme::DEFAULT_WEIGHT,
            kit: theme::kit(theme::DEFAULT_WEIGHT),
            actions: Vec::new(),
            panel: PanelState::default(),
            menu: MenuState::default(),
            palette: PaletteState::default(),
        }
    }

    pub fn set_weight(&mut self, weight: f32) {
        let weight = theme::normalize_weight(weight);
        if weight != self.weight {
            self.weight = weight;
            self.kit = theme::kit(weight);
        }
    }
}

pub fn frame(
    host: &mut Host,
    dt: f64,
    snapshot: *const UiSnapshot,
    panel: *const UiPanel,
    menu: *const UiMenu,
    palette: *const UiPalette,
    events: *const UiEvent,
    count: u32,
) -> i32 {
    let Some(snapshot) = (unsafe { snapshot.as_ref() }) else {
        return 2;
    };
    let Some(runtime) = host.runtime.as_mut() else {
        return 3;
    };

    runtime.state.speed = snapshot.speed;
    runtime.state.grounded = snapshot.grounded != 0;
    runtime.state.menu_open = snapshot.menu_open != 0;
    runtime.state.fx = snapshot.fx != 0;
    runtime.state.set_weight(snapshot.weight);

    if let Some(panel) = unsafe { abi::panel_state(panel) } {
        runtime.state.panel = panel;
    }
    if let Some(menu) = unsafe { abi::menu_state(menu) } {
        runtime.state.menu = menu;
    }
    if let Some(palette) = unsafe { abi::palette_state(palette) } {
        runtime.state.palette = palette;
    }

    input::dispatch(runtime, events, count);

    runtime.invalidate();
    runtime.frame(dt);
    // The overlay does not animate yet. Land mount and exit transitions in the
    // frame that builds them so a capture sees the settled surface.
    runtime.settle_all();
    0
}
