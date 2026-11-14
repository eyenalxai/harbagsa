//! What the harness reads back from a built Rune view: the focused, hovered and
//! pressed control, and the element tree behind an optional report.
use rune::{ElementInfo, Runtime};

use crate::state::UiState;

const INTERNAL_KEYS: [&str; 12] = [
    "label",
    "control",
    "thumb",
    "indicator",
    "trigger",
    "menu",
    "description",
    "kit-root",
    "icon",
    "title",
    "header",
    "body",
];

pub fn interaction(runtime: &mut Runtime<UiState>, out: &mut Interaction) {
    if !runtime.pressing() {
        runtime.state.pressed_key = None;
    } else if runtime.state.pressed_key.is_none() {
        let key = runtime
            .pointer()
            .and_then(|(x, y)| key_at(runtime, x, y));
        runtime.state.pressed_key = key;
    }
    let elements = runtime.elements();
    out.focus = focused_key(&elements);
    out.hover = hovered_key(runtime, &elements);
    out.pressed = if runtime.pressing() {
        runtime.state.pressed_key.clone()
    } else {
        None
    };
}

pub fn element_center(runtime: &Runtime<UiState>, key: &str) -> Option<(f32, f32)> {
    runtime.find(key)
}

pub fn key_at(runtime: &Runtime<UiState>, x: f32, y: f32) -> Option<String> {
    let picked = runtime.element_at(x, y)?;
    let elements = runtime.elements();
    let index = elements
        .iter()
        .position(|element| element.path == picked.path())?;
    control_key(&elements, index)
}

pub fn tree_json(runtime: &Runtime<UiState>) -> String {
    let elements = runtime.elements();
    let mut out = String::with_capacity(elements.len() * 160);
    out.push('[');
    for (index, element) in elements.iter().enumerate() {
        if index > 0 {
            out.push(',');
        }
        out.push('{');
        push_value(&mut out, "path");
        out.push(':');
        push_value(&mut out, &element.path);
        out.push(',');
        push_value(&mut out, "key");
        out.push(':');
        match &element.key {
            Some(key) => push_value(&mut out, key),
            None => out.push_str("null"),
        }
        out.push(',');
        push_value(&mut out, "role");
        out.push(':');
        push_value(&mut out, element.role);
        out.push(',');
        push_value(&mut out, "label");
        out.push(':');
        push_optional(&mut out, element.label.as_deref());
        out.push(',');
        push_value(&mut out, "text");
        out.push(':');
        push_optional(&mut out, element.text.as_deref());
        out.push(',');
        push_value(&mut out, "focused");
        out.push(':');
        out.push_str(bool_text(element.focused));
        out.push(',');
        push_value(&mut out, "focus_visible");
        out.push(':');
        out.push_str(bool_text(element.focus_visible));
        out.push(',');
        push_value(&mut out, "selected");
        out.push(':');
        out.push_str(bool_text(element.item_selected));
        out.push(',');
        push_value(&mut out, "hover");
        out.push(':');
        push_float(&mut out, element.hover);
        out.push(',');
        push_value(&mut out, "press");
        out.push(':');
        push_float(&mut out, element.press);
        out.push(',');
        push_value(&mut out, "opacity");
        out.push(':');
        push_float(&mut out, element.opacity);
        out.push(',');
        push_value(&mut out, "rect");
        out.push(':');
        push_rect(&mut out, element.rect);
        out.push(',');
        push_value(&mut out, "target");
        out.push(':');
        push_rect(&mut out, element.target);
        out.push(',');
        push_value(&mut out, "parent");
        out.push(':');
        match element.parent {
            Some(parent) => out.push_str(&parent.to_string()),
            None => out.push_str("-1"),
        }
        out.push('}');
    }
    out.push(']');
    out
}

#[derive(Default)]
pub struct Interaction {
    pub focus: Option<String>,
    pub hover: Option<String>,
    pub pressed: Option<String>,
}

fn focused_key(elements: &[ElementInfo]) -> Option<String> {
    let index = elements.iter().position(|element| element.focused)?;
    control_key(elements, index)
}

fn hovered_key(runtime: &Runtime<UiState>, elements: &[ElementInfo]) -> Option<String> {
    let (x, y) = runtime.pointer()?;
    let picked = runtime.element_at(x, y)?;
    let index = elements
        .iter()
        .position(|element| element.path == picked.path())?;
    control_key(elements, index)
}

fn control_key(elements: &[ElementInfo], start: usize) -> Option<String> {
    let mut index = Some(start);
    while let Some(at) = index {
        let element = &elements[at];
        if let Some(key) = element.key.as_deref()
            && !internal_key(key)
        {
            return Some(key.to_string());
        }
        index = element.parent;
    }
    None
}

fn internal_key(key: &str) -> bool {
    const SUFFIXES: [&str; 6] = [
        "-layer",
        "-scrim",
        "-dialog",
        "-content",
        "-scroll-area",
        "-trigger",
    ];
    INTERNAL_KEYS.contains(&key)
        || SUFFIXES.iter().any(|suffix| key.ends_with(suffix))
        || key
            .strip_prefix("segment")
            .is_some_and(|rest| !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit()))
}

fn push_optional(out: &mut String, value: Option<&str>) {
    match value {
        Some(value) => push_value(out, value),
        None => out.push_str("null"),
    }
}

fn push_value(out: &mut String, value: &str) {
    out.push('"');
    for character in value.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            character if character < ' ' => {
                out.push_str(&format!("\\u{:04x}", character as u32));
            }
            character => out.push(character),
        }
    }
    out.push('"');
}


fn push_float(out: &mut String, value: f32) {
    if value.is_finite() {
        out.push_str(&format!("{value:.4}"));
    } else {
        out.push_str("0.0");
    }
}

fn push_rect(out: &mut String, rect: [f32; 4]) {
    out.push('[');
    for (index, value) in rect.iter().enumerate() {
        if index > 0 {
            out.push(',');
        }
        push_float(out, *value);
    }
    out.push(']');
}

fn bool_text(value: bool) -> &'static str {
    if value { "true" } else { "false" }
}
