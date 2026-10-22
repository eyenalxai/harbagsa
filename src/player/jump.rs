use bevy::prelude::*;
use bevy_rapier3d::prelude::{Collider, ReadRapierContext};

use super::dive::DiveState;
use super::ground::air_cap;
use super::stance::{PlayerStanceInput, has_headroom, transition_stance};
use super::{
    Player, PlayerCamera, PlayerConfig, PlayerIntent, PlayerMotion, PlayerVelocity, Stance,
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
        &'static mut PlayerMotion,
        &'static DiveState,
    ),
    With<Player>,
>;

pub fn buffer_jump(
    intent: Res<PlayerIntent>,
    config: Res<PlayerConfig>,
    mut players: Query<&mut PlayerMotion, With<Player>>,
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
    if !can_jump(ground.grounded, ground.coyote, ground.jump_buffer) {
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

    let horizontal = velocity.horizontal();
    ground.air_cap = air_cap(config.walk_speed, horizontal.length());
    velocity.0.y = config.jump_speed;
    ground.grounded = false;
    ground.coyote = 0.0;
    ground.jump_buffer = 0.0;
}

pub fn can_jump(grounded: bool, coyote: f32, buffer: f32) -> bool {
    buffer > 0.0 && (grounded || coyote > 0.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jump_from_the_ground_works() {
        assert!(can_jump(true, 0.0, 0.1));
    }

    #[test]
    fn jump_from_coyote_time_works() {
        assert!(can_jump(false, 0.05, 0.1));
    }

    #[test]
    fn jump_in_the_air_without_coyote_fails() {
        assert!(!can_jump(false, 0.0, 0.1));
    }

    #[test]
    fn jump_without_a_buffer_fails() {
        assert!(!can_jump(true, 0.1, 0.0));
    }
}
