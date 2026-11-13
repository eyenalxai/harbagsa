use rune::{El, TextStyle, col, row, spacer};
use rune_kit::{
    Button, ButtonVariant, ControlSize, Dialog, Keybind, Kit, Menu, MenuItem, Placement,
    SegmentedControl, Select, SelectAppearance, Switch,
};

use crate::abi::{
    ACTION_CLOSE_MENU, ACTION_SETTINGS_SET, SETTING_DISPLAY, SETTING_HUD_OPACITY,
    SETTING_REDUCE_MOTION, SETTING_RESOLUTION, SETTING_SPRINT_MODE, SETTING_WINDOW_MODE, UiAction,
};
use crate::components;
use crate::slider;
use crate::state::{
    HUD_OPACITY_MAX, HUD_OPACITY_MIN, SelectKind, UiState,
};
use crate::text;

const DIALOG_WIDTH: f32 = 520.0;
const BODY_WIDTH: f32 = DIALOG_WIDTH - 40.0;
const LABEL_WIDTH: f32 = 160.0;
const CONTROL_WIDTH: f32 = 240.0;
const ROW_HEIGHT: f32 = 40.0;
const HUD_PERCENT_MIN: f32 = HUD_OPACITY_MIN * 100.0;
const HUD_PERCENT_MAX: f32 = HUD_OPACITY_MAX * 100.0;

pub fn dialog(state: &UiState, layers: &mut Vec<El>) {
    if !state.menu.open {
        return;
    }
    let mut select_layers = Vec::new();
    let body = body(state, &mut select_layers);
    let mut dialog = Dialog::new("settings", state.menu.title.clone())
        .open(true)
        .width(DIALOG_WIDTH)
        .fit()
        .on_close(|state: &mut UiState| close(state));
    if !state.menu.note.is_empty() {
        dialog = dialog.description(state.menu.note.clone());
    }
    dialog.child(body).build(&state.kit, layers);
    layers.extend(select_layers);
}

fn body(state: &UiState, select_layers: &mut Vec<El>) -> El {
    let k = &state.kit;
    let bound = opacity_bound(state);
    let resolution_note = if state.settings.resolution_missing {
        "Resolution unavailable"
    } else {
        ""
    };
    col()
        .w_full()
        .padding(20.0)
        .gap(4.0)
        .child(section(k, "Display", resolution_note))
        .child(control_row(k, "Window mode", window_mode(state)))
        .child(control_row(k, "Display", display_select(state, select_layers)))
        .child(control_row(k, "Resolution", resolution_select(state, select_layers)))
        .child(section(k, "Interface", bound))
        .child(opacity(state))
        .child(control_row(k, "Sprint mode", sprint_mode(state)))
        .child(control_row(k, "Reduce motion", reduce_motion(state)))
        .child(section(k, "Controls", ""))
        .child(hints(state))
        .child(components::hairline(k))
        .child(footer(k))
}

fn section(k: &Kit, label: &str, note: &str) -> El {
    let mut header = row().w_full().h(32.0).items_end().child(
        text::styled(
            &label.to_uppercase(),
            TextStyle {
                line_height: 16.0,
                tracking: 0.44,
                ..k.ty.small_medium
            },
        )
        .color(k.c.text_faint),
    );
    if !note.is_empty() {
        header = header
            .child(spacer())
            .child(text::styled(note, k.ty.small).color(k.c.text_faint));
    }
    header
}

fn control_row(k: &Kit, label: &str, control: El) -> El {
    row()
        .w_full()
        .h(ROW_HEIGHT)
        .center_y()
        .gap(12.0)
        .child(text::styled(label, k.ty.ui).color(k.c.text_muted).w(LABEL_WIDTH))
        .child(spacer())
        .child(control)
}

fn window_mode(state: &UiState) -> El {
    let labels: Vec<&str> = state.settings.window_modes.iter().map(String::as_str).collect();
    SegmentedControl::new(
        &labels,
        Some(state.settings.window_mode.min(labels.len().saturating_sub(1))),
    )
    .label("Window mode")
    .width(Some(CONTROL_WIDTH))
    .on_pick(|state: &mut UiState, index, _| {
        push_setting(state, SETTING_WINDOW_MODE, index as i32, 0.0);
    })
    .build(&state.kit)
    .key("settings.window-mode")
}

fn sprint_mode(state: &UiState) -> El {
    let labels: Vec<&str> = state.settings.sprint_modes.iter().map(String::as_str).collect();
    SegmentedControl::new(
        &labels,
        Some(state.settings.sprint_mode.min(labels.len().saturating_sub(1))),
    )
    .label("Sprint mode")
    .width(Some(CONTROL_WIDTH))
    .on_pick(|state: &mut UiState, index, _| {
        push_setting(state, SETTING_SPRINT_MODE, index as i32, 0.0);
    })
    .build(&state.kit)
    .key("settings.sprint-mode")
}

fn display_select(state: &UiState, layers: &mut Vec<El>) -> El {
    select_control(
        state,
        layers,
        SelectKind::Display,
        "settings.display",
        "Display",
        SETTING_DISPLAY,
    )
}

fn resolution_select(state: &UiState, layers: &mut Vec<El>) -> El {
    select_control(
        state,
        layers,
        SelectKind::Resolution,
        "settings.resolution",
        "Resolution",
        SETTING_RESOLUTION,
    )
}

fn select_control(
    state: &UiState,
    layers: &mut Vec<El>,
    kind: SelectKind,
    key: &str,
    label: &str,
    id: u32,
) -> El {
    let (options, current, current_index, disabled, empty) = match kind {
        SelectKind::Display => {
            let options = &state.settings.displays;
            (
                options,
                options.get(state.settings.display).map(String::as_str),
                state.settings.display,
                options.len() <= 1,
                "No display",
            )
        }
        SelectKind::Resolution => {
            let options = &state.settings.resolutions;
            let missing = state.settings.resolution_missing;
            let current = if missing {
                Some(state.settings.resolution_current.as_str())
            } else {
                options.get(state.settings.resolution).map(String::as_str)
            };
            (
                options,
                current,
                if missing { usize::MAX } else { state.settings.resolution },
                options.is_empty()
                    || (state.settings.window_mode == 1 && options.len() == 1),
                "No modes",
            )
        }
    };
    let open = !disabled && state.settings_select == Some(kind);
    let mut select = Select::new(key, options)
        .appearance(SelectAppearance::Field)
        .width(CONTROL_WIDTH)
        .label(label)
        .current(current)
        .placeholder(empty)
        .open(open)
        .on_toggle(move |state: &mut UiState| {
            state.settings_select = if state.settings_select == Some(kind) {
                None
            } else {
                Some(kind)
            };
        });
    if disabled {
        select = select.disabled(true);
    }
    // The kit Select reports the chosen label, not its index. A menu item keeps
    // its own index, so duplicate or truncated display names still select the
    // row the user pressed.
    let mut items = Menu::new(format!("{key}-menu"))
        .trigger(select.trigger(&state.kit))
        .open(open)
        .placement(Placement::BottomEnd)
        .gutter(2.0)
        .min_width(CONTROL_WIDTH)
        .on_close(|state: &mut UiState| state.settings_select = None);
    for (index, name) in options.iter().enumerate() {
        items = items.item(
            MenuItem::new(name.clone())
                .checked(index == current_index)
                .on_select(move |state: &mut UiState| {
                    push_setting(state, id, index as i32, 0.0);
                    state.settings_select = None;
                }),
        );
    }
    items.build(&state.kit, layers)
}

fn opacity_bound(state: &UiState) -> &'static str {
    let value = state
        .opacity_preview
        .unwrap_or(state.settings.hud_opacity)
        .clamp(HUD_OPACITY_MIN, HUD_OPACITY_MAX);
    if value <= HUD_OPACITY_MIN {
        "Minimum"
    } else if value >= HUD_OPACITY_MAX {
        "Maximum"
    } else {
        ""
    }
}

fn opacity(state: &UiState) -> El {
    let value = state
        .opacity_preview
        .unwrap_or(state.settings.hud_opacity)
        .clamp(HUD_OPACITY_MIN, HUD_OPACITY_MAX);
    let percent = (value * 100.0).round();
    let value_text = format!("{percent:.0}%");
    slider::slider(
        &state.kit,
        "settings.opacity",
        "HUD opacity",
        &value_text,
        percent,
        HUD_PERCENT_MIN,
        HUD_PERCENT_MAX,
        1.0,
        BODY_WIDTH,
        |state: &UiState| {
            state
                .opacity_preview
                .unwrap_or(state.settings.hud_opacity)
                .clamp(HUD_OPACITY_MIN, HUD_OPACITY_MAX)
                * 100.0
        },
        |state: &mut UiState, next| {
            let next = next.round().clamp(HUD_PERCENT_MIN, HUD_PERCENT_MAX);
            let previous = state
                .opacity_preview
                .unwrap_or(state.settings.hud_opacity)
                .clamp(HUD_OPACITY_MIN, HUD_OPACITY_MAX)
                * 100.0;
            if (next - previous).abs() < 0.5 {
                return;
            }
            state.opacity_preview = Some(next / 100.0);
            push_setting(state, SETTING_HUD_OPACITY, next as i32, next / 100.0);
        },
    )
}

fn reduce_motion(state: &UiState) -> El {
    Switch::new(state.settings.reduce_motion)
        .label("Reduce motion")
        .hide_label()
        .on_toggle(|state: &mut UiState| {
            let next = !state.settings.reduce_motion;
            push_setting(state, SETTING_REDUCE_MOTION, if next { 1 } else { 0 }, 0.0);
        })
        .build(&state.kit)
        .key("settings.reduce-motion")
}

fn hints(state: &UiState) -> El {
    let mut grid = col().w_full().gap(4.0);
    for chunk in state.menu.hints.chunks(3) {
        let mut line = row().gap(16.0);
        for (keys, action) in chunk {
            line = line
                .child(Keybind::new(&[keys.as_str()]).build(&state.kit))
                .child(text::styled(action, state.kit.ty.small).color(state.kit.c.text_faint));
        }
        grid = grid.child(line);
    }
    grid
}

fn footer(k: &Kit) -> El {
    row().w_full().pt(12.0).justify_end().child(
        Button::new("Resume")
            .variant(ButtonVariant::Submit)
            .control_size(ControlSize::Large)
            .on_press(|state: &mut UiState| close(state))
            .build(k)
            .key("settings.resume"),
    )
}

fn close(state: &mut UiState) {
    state.settings_select = None;
    state.opacity_preview = None;
    state.actions.push(UiAction::new(ACTION_CLOSE_MENU));
}

fn push_setting(state: &mut UiState, id: u32, value: i32, scalar: f32) {
    state.actions.push(UiAction {
        kind: ACTION_SETTINGS_SET,
        id,
        value,
        scalar,
    });
}
