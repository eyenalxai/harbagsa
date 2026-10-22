use bevy::prelude::*;
use bevy_rapier3d::prelude::{Collider, ReadRapierContext};

use super::dive::DiveState;
use super::stance::{PlayerStanceInput, has_headroom, transition_stance};
use super::{
    Player, PlayerCamera, PlayerConfig, PlayerGround, PlayerIntent, PlayerVelocity, Stance,
};

type JumpQuery<'w, 's> = Query<
    'w,
    's,
    (
        Entity,
        &'static mut Transform,
        &'static mut Stance,
        &'static mut Collider,
        &'static mut PlayerStanceInput,
        &'static mut PlayerVelocity,
        &'static mut PlayerGround,
        &'static DiveState,
    ),
    With<Player>,
>;

pub fn buffer_jump(
    intent: Res<PlayerIntent>,
    config: Res<PlayerConfig>,
    mut players: Query<&mut PlayerGround, With<Player>>,
) {
    if !intent.jump_pressed {
        return;
    }

    let Ok(mut ground) = players.single_mut() else {
        return;
    };
    ground.jump_buffer = config.jump_buffer;
}

pub fn apply_jump(
    config: Res<PlayerConfig>,
    rapier: ReadRapierContext,
    mut players: JumpQuery,
    mut cameras: Query<&mut Transform, (With<PlayerCamera>, Without<Player>)>,
) {
    let Ok((
        entity,
        mut transform,
        mut stance,
        mut collider,
        mut stance_input,
        mut velocity,
        mut ground,
        dive,
    )) = players.single_mut()
    else {
        return;
    };

    if *dive != DiveState::None {
        ground.jump_buffer = 0.0;
        return;
    }
    if ground.jump_buffer <= 0.0 {
        return;
    }
    if !ground.grounded && ground.coyote <= 0.0 {
        return;
    }

    if *stance != Stance::Standing {
        let Ok(context) = rapier.single() else {
            return;
        };
        let feet = transform.translation - Vec3::Y * (config.height(*stance) * 0.5);
        if !has_headroom(&context, entity, &config, feet, Stance::Standing) {
            ground.jump_buffer = 0.0;
            return;
        }

        transition_stance(
            &config,
            &mut transform,
            &mut stance,
            &mut collider,
            &mut cameras,
            Stance::Standing,
        );
        stance_input.selection.release();
    }

    let horizontal = Vec3::new(velocity.0.x, 0.0, velocity.0.z);
    ground.air_cap = config.walk_speed.max(horizontal.length());
    velocity.0.y = config.jump_speed;
    ground.grounded = false;
    ground.coyote = 0.0;
    ground.jump_buffer = 0.0;
}
