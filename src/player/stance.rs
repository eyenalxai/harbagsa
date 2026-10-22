use bevy::prelude::*;
use bevy_rapier3d::prelude::{Collider, QueryFilter, RapierContext, ReadRapierContext};

use super::config::InputMode;
use super::dive::DiveState;
use super::gait::PlayerGaitInput;
use super::{Gait, Player, PlayerCamera, PlayerConfig, PlayerIntent, Stance};

/// How far below the real capsule top the headroom probe stops.
/// It keeps a ceiling that exactly matches the target height from counting as a hit.
const HEADROOM_MARGIN: f32 = 0.002;

#[derive(Component, Debug, Default)]
pub struct PlayerStanceInput {
    pub selection: StanceSelection,
    pub dive_requested: bool,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct StanceSelection {
    crouch: bool,
    prone: bool,
}

impl StanceSelection {
    pub fn update(
        &mut self,
        crouch_mode: InputMode,
        crouch_pressed: bool,
        crouch_held: bool,
        prone_mode: InputMode,
        prone_pressed: bool,
        prone_held: bool,
    ) {
        match crouch_mode {
            InputMode::Hold => {
                if crouch_pressed {
                    self.prone = false;
                }
                self.crouch = crouch_held;
            }
            InputMode::Toggle => {
                if crouch_pressed {
                    self.crouch = !self.crouch;
                    if self.crouch {
                        self.prone = false;
                    }
                }
            }
        }

        match prone_mode {
            InputMode::Hold => {
                if prone_pressed {
                    self.crouch = false;
                }
                self.prone = prone_held;
            }
            InputMode::Toggle => {
                if prone_pressed {
                    self.prone = !self.prone;
                    if self.prone {
                        self.crouch = false;
                    }
                }
            }
        }
    }

    pub fn target(self) -> Stance {
        if self.prone {
            Stance::Prone
        } else if self.crouch {
            Stance::Crouching
        } else {
            Stance::Standing
        }
    }

    pub fn release(&mut self) {
        self.crouch = false;
        self.prone = false;
    }
}

pub fn apply_stance_input(
    config: Res<PlayerConfig>,
    intent: Res<PlayerIntent>,
    mut players: Query<&mut PlayerStanceInput, With<Player>>,
) {
    let Ok(mut input) = players.single_mut() else {
        return;
    };

    input.selection.update(
        config.crouch_mode,
        intent.crouch_pressed,
        intent.crouch_held,
        config.prone_mode,
        intent.prone_pressed,
        intent.prone_held,
    );

    if intent.prone_pressed {
        input.dive_requested = true;
    }
}

type StanceQuery<'w, 's> = Query<
    'w,
    's,
    (
        Entity,
        &'static mut Transform,
        &'static mut Stance,
        &'static mut PlayerStanceInput,
        &'static mut PlayerGaitInput,
        &'static mut Gait,
        &'static DiveState,
        &'static mut Collider,
    ),
    With<Player>,
>;

pub fn apply_stance(
    config: Res<PlayerConfig>,
    rapier: ReadRapierContext,
    mut players: StanceQuery,
    mut cameras: Query<&mut Transform, (With<PlayerCamera>, Without<Player>)>,
) {
    let Ok((
        entity,
        mut transform,
        mut stance,
        mut stance_input,
        mut gait_input,
        mut gait,
        dive,
        mut collider,
    )) = players.single_mut()
    else {
        return;
    };

    let sprint_started = gait_input.sprint_started;
    gait_input.sprint_started = false;

    let mut requested = stance_input.selection.target();
    let release_on_sprint = sprint_started;
    if sprint_started {
        requested = Stance::Standing;
    }
    if *dive != DiveState::None {
        requested = Stance::Prone;
    }

    let sprinting =
        gait_input.sprint_engaged && requested == Stance::Standing && *dive == DiveState::None;
    let feet = transform.translation - Vec3::Y * (config.height(*stance) * 0.5);
    let mut new_stance = *stance;
    let mut new_gait = Gait::Walk;

    if sprinting {
        if *stance == Stance::Standing {
            new_gait = Gait::Sprint;
            if release_on_sprint {
                stance_input.selection.release();
            }
        } else {
            let Ok(context) = rapier.single() else {
                *gait = Gait::Walk;
                return;
            };

            if has_headroom(&context, entity, &config, feet, Stance::Standing) {
                new_stance = Stance::Standing;
                new_gait = Gait::Sprint;
                if release_on_sprint {
                    stance_input.selection.release();
                }
            } else if config.sprint_mode == InputMode::Toggle {
                gait_input.blocked = true;
            }
        }
    } else if requested != *stance {
        let Ok(context) = rapier.single() else {
            *gait = Gait::Walk;
            return;
        };

        new_stance = tallest_fitting(&context, entity, &config, feet, requested);
    }

    *gait = new_gait;

    if new_stance == *stance {
        return;
    }

    transition_stance(
        &config,
        &mut transform,
        &mut stance,
        &mut collider,
        &mut cameras,
        new_stance,
    );
}

pub(super) fn transition_stance(
    config: &PlayerConfig,
    transform: &mut Transform,
    stance: &mut Stance,
    collider: &mut Collider,
    cameras: &mut Query<&mut Transform, (With<PlayerCamera>, Without<Player>)>,
    new_stance: Stance,
) {
    if new_stance == *stance {
        return;
    }

    let delta = (config.height(new_stance) - config.height(*stance)) * 0.5;
    transform.translation.y += delta;
    *stance = new_stance;
    *collider = Collider::capsule_y(config.half_height(new_stance), config.capsule_radius);

    if let Ok(mut camera) = cameras.single_mut() {
        camera.translation.y -= delta;
    }
}

fn tallest_fitting(
    context: &RapierContext<'_>,
    player: Entity,
    config: &PlayerConfig,
    feet: Vec3,
    target: Stance,
) -> Stance {
    if target == Stance::Prone {
        return Stance::Prone;
    }

    let standing_fits = stance_rank(target) >= stance_rank(Stance::Standing)
        && has_headroom(context, player, config, feet, Stance::Standing);
    let crouching_fits = stance_rank(target) >= stance_rank(Stance::Crouching)
        && has_headroom(context, player, config, feet, Stance::Crouching);

    choose_stance(target, standing_fits, crouching_fits)
}

pub(super) fn choose_stance(target: Stance, standing_fits: bool, crouching_fits: bool) -> Stance {
    if stance_rank(target) >= stance_rank(Stance::Standing) && standing_fits {
        Stance::Standing
    } else if stance_rank(target) >= stance_rank(Stance::Crouching) && crouching_fits {
        Stance::Crouching
    } else {
        Stance::Prone
    }
}

pub(super) fn has_headroom(
    context: &RapierContext<'_>,
    player: Entity,
    config: &PlayerConfig,
    feet: Vec3,
    stance: Stance,
) -> bool {
    let height = config.height(stance);
    let probe_height = (height - HEADROOM_MARGIN).max(config.capsule_radius * 2.0);
    let half_height = (probe_height * 0.5 - config.capsule_radius).max(0.0);
    let center = feet + Vec3::Y * (probe_height * 0.5);
    let shape = Collider::capsule_y(half_height, config.capsule_radius);
    let filter = QueryFilter::new()
        .exclude_collider(player)
        .exclude_sensors();

    let mut blocked = false;
    context.intersect_shape(center, Quat::IDENTITY, &shape, filter, |_, _| {
        blocked = true;
        false
    });

    !blocked
}

fn stance_rank(stance: Stance) -> u8 {
    match stance {
        Stance::Standing => 2,
        Stance::Crouching => 1,
        Stance::Prone => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn update(
        selection: &mut StanceSelection,
        crouch_mode: InputMode,
        crouch: (bool, bool),
        prone_mode: InputMode,
        prone: (bool, bool),
    ) {
        selection.update(
            crouch_mode,
            crouch.0,
            crouch.1,
            prone_mode,
            prone.0,
            prone.1,
        );
    }

    #[test]
    fn toggle_crouch_twice_returns_to_standing() {
        let mut selection = StanceSelection::default();
        update(
            &mut selection,
            InputMode::Toggle,
            (true, true),
            InputMode::Toggle,
            (false, false),
        );
        assert_eq!(selection.target(), Stance::Crouching);

        update(
            &mut selection,
            InputMode::Toggle,
            (true, false),
            InputMode::Toggle,
            (false, false),
        );
        assert_eq!(selection.target(), Stance::Standing);
    }

    #[test]
    fn prone_press_clears_crouch() {
        let mut selection = StanceSelection::default();
        update(
            &mut selection,
            InputMode::Toggle,
            (true, true),
            InputMode::Toggle,
            (false, false),
        );
        update(
            &mut selection,
            InputMode::Toggle,
            (false, false),
            InputMode::Toggle,
            (true, true),
        );
        assert_eq!(selection.target(), Stance::Prone);
    }

    #[test]
    fn prone_press_twice_returns_to_standing() {
        let mut selection = StanceSelection::default();
        update(
            &mut selection,
            InputMode::Toggle,
            (false, false),
            InputMode::Toggle,
            (true, true),
        );
        update(
            &mut selection,
            InputMode::Toggle,
            (false, false),
            InputMode::Toggle,
            (true, false),
        );
        assert_eq!(selection.target(), Stance::Standing);
    }

    #[test]
    fn hold_crouch_returns_to_standing_on_release() {
        let mut selection = StanceSelection::default();
        update(
            &mut selection,
            InputMode::Hold,
            (true, true),
            InputMode::Toggle,
            (false, false),
        );
        assert_eq!(selection.target(), Stance::Crouching);

        update(
            &mut selection,
            InputMode::Hold,
            (false, false),
            InputMode::Toggle,
            (false, false),
        );
        assert_eq!(selection.target(), Stance::Standing);
    }

    #[test]
    fn hold_crouch_with_prone_toggle_prefers_prone() {
        let mut selection = StanceSelection::default();
        update(
            &mut selection,
            InputMode::Hold,
            (true, true),
            InputMode::Toggle,
            (true, true),
        );
        assert_eq!(selection.target(), Stance::Prone);

        update(
            &mut selection,
            InputMode::Hold,
            (false, true),
            InputMode::Toggle,
            (true, false),
        );
        assert_eq!(selection.target(), Stance::Crouching);

        update(
            &mut selection,
            InputMode::Hold,
            (false, true),
            InputMode::Toggle,
            (false, false),
        );
        assert_eq!(selection.target(), Stance::Crouching);
    }

    #[test]
    fn hold_prone_returns_to_crouch_when_crouch_is_toggled() {
        let mut selection = StanceSelection::default();
        update(
            &mut selection,
            InputMode::Toggle,
            (true, true),
            InputMode::Hold,
            (false, true),
        );
        assert_eq!(selection.target(), Stance::Prone);

        update(
            &mut selection,
            InputMode::Toggle,
            (false, false),
            InputMode::Hold,
            (false, false),
        );
        assert_eq!(selection.target(), Stance::Crouching);

        update(
            &mut selection,
            InputMode::Toggle,
            (false, false),
            InputMode::Hold,
            (false, false),
        );
        assert_eq!(selection.target(), Stance::Crouching);
    }

    #[test]
    fn stance_rank_orders_standing_above_prone() {
        assert!(stance_rank(Stance::Standing) > stance_rank(Stance::Crouching));
        assert!(stance_rank(Stance::Crouching) > stance_rank(Stance::Prone));
    }

    #[test]
    fn standing_is_kept_when_it_fits() {
        assert_eq!(
            choose_stance(Stance::Standing, true, true),
            Stance::Standing
        );
    }

    #[test]
    fn standing_falls_back_to_crouching() {
        assert_eq!(
            choose_stance(Stance::Standing, false, true),
            Stance::Crouching
        );
    }

    #[test]
    fn standing_falls_back_to_prone() {
        assert_eq!(choose_stance(Stance::Standing, false, false), Stance::Prone);
    }

    #[test]
    fn crouching_never_chooses_standing() {
        assert_eq!(
            choose_stance(Stance::Crouching, true, true),
            Stance::Crouching
        );
    }

    #[test]
    fn a_prone_target_never_grows() {
        assert_eq!(choose_stance(Stance::Prone, true, true), Stance::Prone);
    }
}
