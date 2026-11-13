use rune::{Drag, El, Phase, Tx, col, el, row, spacer};
use rune_kit::Kit;

use crate::text;

const TRACK: f32 = 4.0;
const KNOB: f32 = 14.0;
const HEIGHT: f32 = 24.0;

/// The kit has no Slider. This one owns the drag, the track press, the keyboard
/// step, and the cancel restore; the caller owns the value.
pub fn slider<S: 'static>(
    k: &Kit,
    key: &str,
    label: &str,
    value_text: &str,
    value: f32,
    min: f32,
    max: f32,
    step: f32,
    width: f32,
    value_of: impl Fn(&S) -> f32 + Clone + 'static,
    on_change: impl Fn(&mut S, f32) + Clone + 'static,
) -> El {
    let span = (max - min).max(step);
    let travel = (width - KNOB).max(1.0);
    let ratio = move |v: f32| ((v.clamp(min, max) - min) / span).clamp(0.0, 1.0);
    let to_value = move |x: f32, w: f32| {
        let travel = (w - KNOB).max(1.0);
        (((x - KNOB / 2.0) / travel).clamp(0.0, 1.0) * span + min).clamp(min, max)
    };
    let snap = move |v: f32| ((v / step).round() * step).clamp(min, max);

    let step_value = value_of.clone();
    let step_change = on_change.clone();
    let limit_change = on_change.clone();
    let drag_value = value_of;
    let drag_change = on_change;

    col()
        .w(width)
        .gap(4.0)
        .child(
            row()
                .w_full()
                .h(16.0)
                .center_y()
                .child(text::styled(label, k.ty.ui).color(k.c.text_muted).a11y_hidden())
                .child(spacer())
                .child(text::styled(value_text, k.ty.mono).color(k.c.text_base).a11y_hidden()),
        )
        .child(
            el()
                .key(key)
                .role("slider")
                .label(label)
                .focusable(true)
                .focus_ring(2.0, 1.0, k.c.border_focus)
                .w(width)
                .h(HEIGHT)
                .range_value(value as f64, min as f64, max as f64)
                .range_step(step as f64)
                .a11y_value(value_text.to_owned())
                .on_step(move |state: &mut S, steps: i32, tx: &mut Tx| {
                    let next = snap(step_value(state) + steps as f32 * step);
                    step_change(state, next);
                    tx.instant();
                })
                .on_step_limit(move |state: &mut S, maximum: bool, tx: &mut Tx| {
                    limit_change(state, if maximum { max } else { min });
                    tx.instant();
                })
                .on_drag(move |state: &mut S, drag: &mut Drag, tx: &mut Tx| {
                    let travel = (drag.w - KNOB).max(1.0);
                    match drag.phase {
                        Phase::Down => {
                            drag.data = drag_value(state);
                            let knob = KNOB / 2.0 + ratio(drag.data) * travel;
                            if (drag.x - knob).abs() > KNOB / 2.0 + 2.0 {
                                drag_change(state, snap(to_value(drag.x, drag.w)));
                                tx.instant();
                            }
                        }
                        Phase::Move => {
                            let knob = KNOB / 2.0 + ratio(drag.data) * travel;
                            let grab = if (drag.start_x - knob).abs() <= KNOB / 2.0 + 2.0 {
                                drag.start_x - knob
                            } else {
                                0.0
                            };
                            let next = snap(to_value(drag.x - grab, drag.w));
                            if next != drag_value(state) {
                                drag_change(state, next);
                            }
                            tx.instant();
                        }
                        Phase::Up => {
                            if drag.cancelled() {
                                drag_change(state, drag.data);
                            }
                        }
                    }
                })
                .child(
                    el()
                        .absolute(0.0, (HEIGHT - TRACK) / 2.0)
                        .w_full()
                        .h(TRACK)
                        .radius(TRACK / 2.0)
                        .fill(k.light(0.20))
                        .a11y_hidden(),
                )
                .child(
                    el()
                        .absolute(0.0, (HEIGHT - TRACK) / 2.0)
                        .w(KNOB / 2.0 + ratio(value) * travel)
                        .h(TRACK)
                        .radius(TRACK / 2.0)
                        .fill(k.c.bg_accent)
                        .a11y_hidden(),
                )
                .child(
                    k.elevate(
                        el()
                            .absolute(ratio(value) * travel, (HEIGHT - KNOB) / 2.0)
                            .size(KNOB, KNOB)
                            .radius(KNOB / 2.0)
                            .fill(k.c.knob)
                            .border(1.0, k.c.border_strong),
                        &k.elevation.elements,
                    )
                    .a11y_hidden(),
                ),
        )
}
