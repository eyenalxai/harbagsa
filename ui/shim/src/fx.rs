use rune::render::{EffectSite, KIND_EFFECT};
use rune::Runtime;
use rune_fx::{Fx, FxLayer, FxRenderer, FxSlot, GlowParams, Shape, rgb};

use crate::state::UiState;
use crate::theme;

pub const GLOW: u32 = 1;

pub struct FxSlotPlan {
    pub instance: u32,
    pub layer: usize,
}

pub struct FxPlan {
    pub layers: Vec<FxLayer>,
    pub slots: Vec<FxSlot>,
    pub effects: Vec<FxSlotPlan>,
}

pub fn plan(runtime: &Runtime<UiState>) -> FxPlan {
    // Layers and slots upload before the pass; the hook can only draw them.
    let mut layers = Vec::new();
    let mut slots = Vec::new();
    let mut effects = Vec::new();
    for (index, instance) in runtime.instances.iter().enumerate() {
        if instance.params[1] != KIND_EFFECT {
            continue;
        }
        let mark = instance.border[0] as u32 | ((instance.border[1] as u32) << 16);
        if mark != GLOW {
            continue;
        }
        let k = instance.params[3];
        let [x, y, w, h] = instance.rect;
        let glow = Fx::glow(GlowParams {
            color: rgb(theme::FX_GLOW_COLOR),
            core: rgb(theme::FX_GLOW_CORE),
            intensity: instance.uv[0].clamp(0.0, 3.0),
            radius: 12.0,
            ..Default::default()
        });
        layers.push(glow.on(Shape::rounded(x / k, y / k, w / k, h / k, 0.0)));
        slots.push(FxSlot::default().scale(k).clip(instance.clip, instance.fade));
        effects.push(FxSlotPlan {
            instance: index as u32,
            layer: layers.len() - 1,
        });
    }
    FxPlan { layers, slots, effects }
}

pub fn draw(
    fx: &FxRenderer,
    plans: &[FxSlotPlan],
    pass: &mut wgpu::RenderPass<'_>,
    site: &EffectSite<'_>,
) {
    if site.mark != GLOW {
        return;
    }
    let Some(plan) = plans.iter().find(|plan| plan.instance == site.index) else {
        return;
    };
    if site.in_layer {
        fx.draw_layer_in(pass, site.format, site.origin, plan.layer);
    } else {
        fx.draw_layer(pass, plan.layer);
    }
}
