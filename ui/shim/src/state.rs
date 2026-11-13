use rune_kit::Kit;

use crate::abi::{
    self, UiAction, UiEvent, UiInspector, UiMenu, UiPalette, UiPanel, UiSettings, UiSnapshot,
};
use crate::{host::Host, input, theme};

pub const HUD_OPACITY_MIN: f32 = 0.70;
pub const HUD_OPACITY_MAX: f32 = 1.00;
pub const HUD_OPACITY_DEFAULT: f32 = 0.94;
pub const HUD_OPACITY_PROMOTE: f32 = 0.94;

#[derive(Default)]
pub struct PanelRow {
    pub kind: u32,
    pub flags: u32,
    pub label: String,
    pub value: String,
}

#[derive(Default)]
pub struct MenuState {
    pub open: bool,
    pub title: String,
    pub note: String,
    pub hints: Vec<(String, String)>,
}

#[derive(Default)]
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

#[derive(Default)]
pub struct PaletteState {
    pub open: bool,
    pub title: String,
    pub items: Vec<PaletteItem>,
    pub selected: usize,
    pub body: String,
    pub size: String,
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

#[derive(Default)]
pub struct InspectorState {
    pub open: bool,
    pub has_selection: bool,
    pub object_id: u32,
    pub selection: String,
    pub body: usize,
    pub yaw_degrees: f32,
    pub yaw_text: String,
    pub placement_prefab: String,
    pub placement_height_text: String,
    pub placement_yaw_text: String,
    pub placement_snap_text: String,
    pub has_lamp: bool,
    pub lamp_kind: usize,
    pub lamp_color: usize,
    pub lamp_intensity: f32,
    pub lamp_range: f32,
    pub lamp_intensity_text: String,
    pub lamp_range_text: String,
    pub lamp_colors: [[f32; 4]; 5],
    pub type_weight: f32,
    pub type_weight_text: String,
    pub physics_debug: bool,
}

#[derive(Default)]
pub struct InspectorPreview {
    pub yaw: Option<f32>,
    pub intensity: Option<f32>,
    pub range: Option<f32>,
    pub weight: Option<f32>,
}

pub struct SettingsState {
    pub window_mode: usize,
    pub window_modes: Vec<String>,
    pub display: usize,
    pub displays: Vec<String>,
    pub resolution: usize,
    pub resolutions: Vec<String>,
    pub resolution_current: String,
    pub resolution_missing: bool,
    pub sprint_mode: usize,
    pub sprint_modes: Vec<String>,
    pub hud_opacity: f32,
    pub reduce_motion: bool,
}

impl Default for SettingsState {
    fn default() -> Self {
        Self {
            window_mode: 0,
            window_modes: Vec::new(),
            display: 0,
            displays: Vec::new(),
            resolution: 0,
            resolutions: Vec::new(),
            resolution_current: String::new(),
            resolution_missing: false,
            sprint_mode: 0,
            sprint_modes: Vec::new(),
            hud_opacity: HUD_OPACITY_DEFAULT,
            reduce_motion: false,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum SelectKind {
    Display,
    Resolution,
}

pub struct UiState {
    pub speed: f32,
    pub grounded: bool,
    pub menu_open: bool,
    pub fx: bool,
    pub weight: f32,
    pub viewport: (f32, f32),
    pub kit: Kit,
    pub actions: Vec<UiAction>,
    pub panel: PanelState,
    pub menu: MenuState,
    pub settings: SettingsState,
    pub settings_select: Option<SelectKind>,
    pub opacity_preview: Option<f32>,
    pub palette: PaletteState,
    pub inspector: InspectorState,
    pub inspector_preview: InspectorPreview,
}

impl UiState {
    pub fn new() -> Self {
        Self {
            speed: 0.0,
            grounded: false,
            menu_open: false,
            fx: false,
            weight: theme::DEFAULT_WEIGHT,
            viewport: (0.0, 0.0),
            kit: theme::kit(theme::DEFAULT_WEIGHT),
            actions: Vec::new(),
            panel: PanelState::default(),
            menu: MenuState::default(),
            settings: SettingsState::default(),
            settings_select: None,
            opacity_preview: None,
            palette: PaletteState::default(),
            inspector: InspectorState::default(),
            inspector_preview: InspectorPreview::default(),
        }
    }

    pub fn set_weight(&mut self, weight: f32) {
        let weight = theme::normalize_weight(weight);
        if weight != self.weight {
            self.weight = weight;
            self.kit = theme::kit(weight);
        }
    }

    pub fn clear_inspector_previews(&mut self) {
        let inspector = &self.inspector;
        let preview = &mut self.inspector_preview;
        if let Some(value) = preview.yaw {
            let normalized = normalize_degrees(value);
            preview.yaw = if (normalized - inspector.yaw_degrees).abs() < 0.05 {
                None
            } else {
                Some(normalized)
            };
        }
        if preview
            .intensity
            .is_some_and(|value| (value - inspector.lamp_intensity).abs() < 0.0005)
        {
            preview.intensity = None;
        }
        if preview
            .range
            .is_some_and(|value| (value - inspector.lamp_range).abs() < 0.05)
        {
            preview.range = None;
        }
        if preview
            .weight
            .is_some_and(|value| (value - inspector.type_weight).abs() < 0.5)
        {
            preview.weight = None;
        }
        if !inspector.open {
            *preview = InspectorPreview::default();
            return;
        }
        if !inspector.has_selection {
            preview.yaw = None;
        }
        if !inspector.has_lamp {
            preview.intensity = None;
            preview.range = None;
        }
    }
}

fn normalize_degrees(value: f32) -> f32 {
    value - 360.0 * (value / 360.0).floor()
}

pub fn frame(
    host: &mut Host,
    dt: f64,
    snapshot: *const UiSnapshot,
    panel: *const UiPanel,
    menu: *const UiMenu,
    settings: *const UiSettings,
    palette: *const UiPalette,
    inspector: *const UiInspector,
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
    runtime.state.viewport = (snapshot.viewport_width, snapshot.viewport_height);
    runtime.state.set_weight(snapshot.weight);

    if let Some(panel) = unsafe { abi::panel_state(panel) } {
        runtime.state.panel = panel;
    }
    if let Some(menu) = unsafe { abi::menu_state(menu) } {
        runtime.state.menu = menu;
    }
    runtime.state.menu.open = runtime.state.menu_open;
    if let Some(settings) = unsafe { abi::settings_state(settings) } {
        runtime.state.settings = settings;
        runtime.state.settings.hud_opacity = runtime
            .state
            .settings
            .hud_opacity
            .clamp(HUD_OPACITY_MIN, HUD_OPACITY_MAX);
        if runtime
            .state
            .opacity_preview
            .is_some_and(|preview| (preview - runtime.state.settings.hud_opacity).abs() < 0.0005)
        {
            runtime.state.opacity_preview = None;
        }
    }
    if !runtime.state.menu_open {
        runtime.state.settings_select = None;
        runtime.state.opacity_preview = None;
    }
    if let Some(palette) = unsafe { abi::palette_state(palette) } {
        runtime.state.palette = palette;
    }
    if let Some(inspector) = unsafe { abi::inspector_state(inspector) } {
        runtime.state.inspector = inspector;
    }
    runtime.state.clear_inspector_previews();

    input::dispatch(runtime, events, count);

    runtime.invalidate();
    runtime.frame(dt);
    0
}
