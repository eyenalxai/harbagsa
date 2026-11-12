use rune::render::EffectPhase;

use crate::fx;
use crate::host::Host;

pub fn draw(host: &mut Host, image_index: u32) -> i32 {
    let index = image_index as usize;
    if index >= host.views.len() {
        return 2;
    }
    let Some(format) = host.format else {
        return 3;
    };
    let Some(runtime) = host.runtime.as_mut() else {
        return 4;
    };
    let Some(renderer) = host.renderer.as_mut() else {
        return 5;
    };

    renderer.prepare(
        &host.device,
        &host.queue,
        &mut runtime.text.atlas,
        &runtime.instances,
        (host.width, host.height),
    );
    let plan = fx::plan(runtime);
    if let Some(fx) = host.fx.as_mut() {
        let _ = fx.prepare_with_slots(
            &host.device,
            &host.queue,
            &rune_fx::FxFrame {
                viewport: [host.width, host.height],
                scale: host.scale,
                layers: &plan.layers,
                backdrop: None,
                sources: &[],
            },
            &plan.slots,
        );
    }
    let fx_renderer = host.fx.as_ref();
    let mut encoder = host
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("rune-ui") });
    renderer.encode_layers_with(&mut encoder, &mut |pass, site| {
        if site.in_layer {
            if let Some(fx) = fx_renderer {
                fx::draw(fx, &plan.effects, pass, site);
            }
        }
    });
    renderer.draw_target_range_with(
        &mut encoder,
        &host.views[index],
        format,
        wgpu::LoadOp::Load,
        0..runtime.instances.len() as u32,
        &mut |phase, site| {
            if let EffectPhase::Draw(pass) = phase {
                if !site.in_layer {
                    if let Some(fx) = fx_renderer {
                        fx::draw(fx, &plan.effects, pass, site);
                    }
                }
            }
        },
    );
    let submission = renderer.submit(&host.queue, encoder);
    if host
        .device
        .poll(wgpu::PollType::Wait {
            submission_index: Some(submission),
            timeout: None,
        })
        .is_err()
    {
        return 6;
    }
    0
}
