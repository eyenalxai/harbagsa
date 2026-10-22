use bevy::prelude::*;
use bevy_rapier3d::prelude::{Collider, ColliderMassProperties, RigidBody};

#[derive(Resource, Debug, Clone, Copy)]
pub struct PlayerSpawn {
    pub feet: Vec3,
}

impl Default for PlayerSpawn {
    fn default() -> Self {
        Self {
            feet: Vec3::new(0.0, 0.05, 14.0),
        }
    }
}

pub struct ArenaPlugin;

impl Plugin for ArenaPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PlayerSpawn>()
            .add_systems(Startup, spawn_arena);
    }
}

const RAMP_THICKNESS: f32 = 0.25;
const RAMP_DECK_DEPTH: f32 = 1.5;
const TUNNEL_WIDTH: f32 = 2.0;
const TUNNEL_WALL: f32 = 0.3;
const TUNNEL_CEILING: f32 = 0.3;

struct ArenaMaterials {
    floor: Handle<StandardMaterial>,
    wall: Handle<StandardMaterial>,
    walkable: Handle<StandardMaterial>,
    tunnel: Handle<StandardMaterial>,
    dive: Handle<StandardMaterial>,
    marker: Handle<StandardMaterial>,
    landing: Handle<StandardMaterial>,
}

impl ArenaMaterials {
    fn new(materials: &mut Assets<StandardMaterial>) -> Self {
        Self {
            floor: material(materials, Color::srgb(0.16, 0.17, 0.20), 0.95),
            wall: material(materials, Color::srgb(0.09, 0.10, 0.12), 0.90),
            walkable: material(materials, Color::srgb(0.18, 0.40, 0.80), 0.70),
            tunnel: material(materials, Color::srgb(0.90, 0.42, 0.08), 0.80),
            dive: material(materials, Color::srgb(0.10, 0.62, 0.28), 0.65),
            marker: material(materials, Color::srgb(0.90, 0.92, 0.95), 0.60),
            landing: material(materials, Color::srgb(0.45, 0.85, 0.55), 0.70),
        }
    }
}

fn material(
    materials: &mut Assets<StandardMaterial>,
    base_color: Color,
    perceptual_roughness: f32,
) -> Handle<StandardMaterial> {
    materials.add(StandardMaterial {
        base_color,
        perceptual_roughness,
        ..default()
    })
}

fn spawn_arena(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let materials = ArenaMaterials::new(&mut materials);

    spawn_shell(&mut commands, &mut meshes, &materials);
    spawn_sprint_lane(&mut commands, &mut meshes, &materials);
    spawn_staircase(&mut commands, &mut meshes, &materials);
    spawn_stance_steps(&mut commands, &mut meshes, &materials);
    spawn_ramps(&mut commands, &mut meshes, &materials);
    spawn_tunnels(&mut commands, &mut meshes, &materials);
    spawn_dive_platform(&mut commands, &mut meshes, &materials);
    spawn_crates(&mut commands, &mut meshes, &materials);
}

fn spawn_shell(commands: &mut Commands, meshes: &mut Assets<Mesh>, materials: &ArenaMaterials) {
    spawn_box(
        commands,
        meshes,
        &materials.floor,
        Vec3::new(0.0, -0.5, 0.0),
        Vec3::new(40.0, 1.0, 40.0),
    );

    let wall_size = Vec3::new(41.0, 4.0, 1.0);
    let side_wall_size = Vec3::new(1.0, 4.0, 41.0);
    for z in [-20.5, 20.5] {
        spawn_box(
            commands,
            meshes,
            &materials.wall,
            Vec3::new(0.0, 2.0, z),
            wall_size,
        );
    }
    for x in [-20.5, 20.5] {
        spawn_box(
            commands,
            meshes,
            &materials.wall,
            Vec3::new(x, 2.0, 0.0),
            side_wall_size,
        );
    }

    commands.spawn((
        DirectionalLight {
            illuminance: 8_000.0,
            shadow_maps_enabled: true,
            ..default()
        },
        Transform::from_xyz(12.0, 20.0, 8.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));

    for (position, intensity) in [
        (Vec3::new(3.0, 1.00, -8.0), 60_000.0),
        (Vec3::new(9.0, 1.10, -8.0), 80_000.0),
        (Vec3::new(15.0, 0.70, -8.0), 50_000.0),
        (Vec3::new(-12.0, 4.0, 12.0), 100_000.0),
    ] {
        commands.spawn((
            PointLight {
                intensity,
                range: 8.0,
                ..default()
            },
            Transform::from_translation(position),
        ));
    }

    commands.insert_resource(GlobalAmbientLight {
        color: Color::srgb(0.55, 0.65, 0.80),
        brightness: 200.0,
        ..default()
    });
}

fn spawn_sprint_lane(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &ArenaMaterials,
) {
    const START_X: f32 = -18.0;
    const LENGTH: f32 = 20.0;
    const WIDTH: f32 = 2.0;

    spawn_box(
        commands,
        meshes,
        &materials.walkable,
        Vec3::new(START_X + LENGTH * 0.5, 0.01, 0.0),
        Vec3::new(LENGTH, 0.02, WIDTH),
    );

    for distance in [0.0_f32, 5.0, 10.0, 15.0, 20.0] {
        spawn_box(
            commands,
            meshes,
            &materials.marker,
            Vec3::new(START_X + distance, 0.03, 0.0),
            Vec3::new(0.12, 0.02, WIDTH + 0.4),
        );
    }
}

fn spawn_staircase(commands: &mut Commands, meshes: &mut Assets<Mesh>, materials: &ArenaMaterials) {
    const STEP_COUNT: u32 = 10;
    const RISE: f32 = 0.2;
    const RUN: f32 = 0.3;

    // Ten 0.20 m steps with a 0.30 m tread, rising toward -Z.
    spawn_stairs(
        commands,
        meshes,
        &materials.walkable,
        StairsSpec {
            center_x: -14.0,
            width: 3.0,
            tall_z: -8.0,
            step_count: STEP_COUNT,
            rise: RISE,
            run: RUN,
        },
    );

    let top = RISE * STEP_COUNT as f32;
    spawn_box(
        commands,
        meshes,
        &materials.walkable,
        Vec3::new(-14.0, top * 0.5, -8.75),
        Vec3::new(3.0, top, 1.5),
    );
}

fn spawn_stance_steps(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &ArenaMaterials,
) {
    // 0.35 m passes the autostep; 0.50 m blocks it.
    spawn_box(
        commands,
        meshes,
        &materials.walkable,
        Vec3::new(-17.0, 0.175, -12.5),
        Vec3::new(2.0, 0.35, 2.0),
    );
    spawn_box(
        commands,
        meshes,
        &materials.walkable,
        Vec3::new(-12.5, 0.25, -12.5),
        Vec3::new(2.0, 0.5, 2.0),
    );
}

fn spawn_ramps(commands: &mut Commands, meshes: &mut Assets<Mesh>, materials: &ArenaMaterials) {
    let ramps = [
        RampSpec {
            angle_degrees: 20.0,
            low_x: 8.0,
            z: 15.0,
            width: 3.0,
            run: 4.0,
        },
        RampSpec {
            angle_degrees: 40.0,
            low_x: 8.0,
            z: 11.0,
            width: 3.0,
            run: 3.0,
        },
        RampSpec {
            angle_degrees: 50.0,
            low_x: 8.0,
            z: 7.0,
            width: 3.0,
            run: 2.0,
        },
    ];

    for ramp in ramps {
        spawn_ramp(commands, meshes, &materials.walkable, ramp);
    }
}

fn spawn_tunnels(commands: &mut Commands, meshes: &mut Assets<Mesh>, materials: &ArenaMaterials) {
    let tunnels = [
        TunnelSpec {
            center_x: 3.0,
            center_z: -8.0,
            // The controller keeps a 0.01 m gap under the feet, so 1.20 m would not fit a crouch.
            clearance: 1.22,
            length: 4.0,
        },
        TunnelSpec {
            center_x: 9.0,
            center_z: -8.0,
            clearance: 1.35,
            length: 4.0,
        },
        TunnelSpec {
            center_x: 15.0,
            center_z: -8.0,
            clearance: 0.9,
            length: 4.0,
        },
    ];

    for tunnel in tunnels {
        spawn_tunnel(commands, meshes, &materials.tunnel, tunnel);
    }
}

fn spawn_dive_platform(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &ArenaMaterials,
) {
    const CENTER_X: f32 = -12.0;
    const CENTER_Z: f32 = 12.0;
    const HEIGHT: f32 = 2.5;
    const SIZE: f32 = 4.0;
    const STEP_COUNT: u32 = 10;

    spawn_box(
        commands,
        meshes,
        &materials.dive,
        Vec3::new(CENTER_X, HEIGHT * 0.5, CENTER_Z),
        Vec3::new(SIZE, HEIGHT, SIZE),
    );

    // Access stairs on the back side. Ten 0.25 m steps reach the 2.5 m deck.
    spawn_stairs(
        commands,
        meshes,
        &materials.walkable,
        StairsSpec {
            center_x: CENTER_X,
            width: 2.0,
            tall_z: CENTER_Z + SIZE * 0.5,
            step_count: STEP_COUNT,
            rise: HEIGHT / STEP_COUNT as f32,
            run: 0.3,
        },
    );

    // Marked landing zone on the floor, in front of the dive edge.
    spawn_box(
        commands,
        meshes,
        &materials.landing,
        Vec3::new(CENTER_X, 0.01, 6.5),
        Vec3::new(SIZE, 0.02, 7.0),
    );
}

fn spawn_crates(commands: &mut Commands, meshes: &mut Assets<Mesh>, materials: &ArenaMaterials) {
    const SIZE: f32 = 0.6;
    const HALF: f32 = SIZE * 0.5;
    const MASS: f32 = 20.0;

    let mesh = meshes.add(Cuboid::new(SIZE, SIZE, SIZE));

    for position in [
        Vec3::new(5.5, HALF + 0.01, 4.0),
        Vec3::new(6.3, HALF + 0.01, 4.0),
        Vec3::new(7.1, HALF + 0.01, 4.0),
    ] {
        commands.spawn((
            Mesh3d(mesh.clone()),
            MeshMaterial3d(materials.walkable.clone()),
            Transform::from_translation(position),
            RigidBody::Dynamic,
            Collider::cuboid(HALF, HALF, HALF),
            ColliderMassProperties::Mass(MASS),
        ));
    }
}

struct StairsSpec {
    center_x: f32,
    width: f32,
    tall_z: f32,
    step_count: u32,
    rise: f32,
    run: f32,
}

fn spawn_stairs(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    material: &Handle<StandardMaterial>,
    spec: StairsSpec,
) {
    for index in 0..spec.step_count {
        let step = index as f32;
        let height = spec.rise * (step + 1.0);
        let center_z = spec.tall_z + spec.run * (spec.step_count as f32 - step - 0.5);
        spawn_box(
            commands,
            meshes,
            material,
            Vec3::new(spec.center_x, height * 0.5, center_z),
            Vec3::new(spec.width, height, spec.run),
        );
    }
}

#[derive(Clone, Copy)]
struct RampSpec {
    angle_degrees: f32,
    low_x: f32,
    z: f32,
    width: f32,
    run: f32,
}

impl RampSpec {
    fn angle(self) -> f32 {
        self.angle_degrees.to_radians()
    }

    fn height(self) -> f32 {
        self.run * self.angle().tan()
    }

    fn slab_size(self) -> Vec3 {
        Vec3::new(self.run / self.angle().cos(), RAMP_THICKNESS, self.width)
    }

    fn slab_center(self) -> Vec3 {
        let angle = self.angle();
        Vec3::new(
            self.low_x + self.run * 0.5 + RAMP_THICKNESS * 0.5 * angle.sin(),
            self.height() * 0.5 - RAMP_THICKNESS * 0.5 * angle.cos(),
            self.z,
        )
    }

    fn rotation(self) -> Quat {
        Quat::from_rotation_z(self.angle())
    }
}

fn spawn_ramp(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    material: &Handle<StandardMaterial>,
    spec: RampSpec,
) {
    // The slab top surface meets the floor at the low end and the deck at the high end.
    spawn_rotated_box(
        commands,
        meshes,
        material,
        spec.slab_center(),
        spec.slab_size(),
        spec.rotation(),
    );

    let height = spec.height();
    spawn_box(
        commands,
        meshes,
        material,
        Vec3::new(
            spec.low_x + spec.run + RAMP_DECK_DEPTH * 0.5,
            height * 0.5,
            spec.z,
        ),
        Vec3::new(RAMP_DECK_DEPTH, height, spec.width),
    );
}

struct TunnelSpec {
    center_x: f32,
    center_z: f32,
    clearance: f32,
    length: f32,
}

fn spawn_tunnel(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    material: &Handle<StandardMaterial>,
    spec: TunnelSpec,
) {
    let wall_height = spec.clearance + TUNNEL_CEILING;
    let wall_offset = TUNNEL_WIDTH * 0.5 + TUNNEL_WALL * 0.5;

    for side in [-1.0_f32, 1.0] {
        spawn_box(
            commands,
            meshes,
            material,
            Vec3::new(
                spec.center_x + side * wall_offset,
                wall_height * 0.5,
                spec.center_z,
            ),
            Vec3::new(TUNNEL_WALL, wall_height, spec.length),
        );
    }

    spawn_box(
        commands,
        meshes,
        material,
        Vec3::new(
            spec.center_x,
            spec.clearance + TUNNEL_CEILING * 0.5,
            spec.center_z,
        ),
        Vec3::new(
            TUNNEL_WIDTH + TUNNEL_WALL * 2.0,
            TUNNEL_CEILING,
            spec.length,
        ),
    );
}

fn spawn_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    material: &Handle<StandardMaterial>,
    center: Vec3,
    size: Vec3,
) {
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(size.x, size.y, size.z))),
        MeshMaterial3d(material.clone()),
        Transform::from_translation(center),
        Collider::cuboid(size.x * 0.5, size.y * 0.5, size.z * 0.5),
    ));
}

fn spawn_rotated_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    material: &Handle<StandardMaterial>,
    center: Vec3,
    size: Vec3,
    rotation: Quat,
) {
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(size.x, size.y, size.z))),
        MeshMaterial3d(material.clone()),
        Transform::from_translation(center).with_rotation(rotation),
        Collider::cuboid(size.x * 0.5, size.y * 0.5, size.z * 0.5),
    ));
}

#[cfg(test)]
mod tests {
    use super::{RAMP_THICKNESS, RampSpec};
    use bevy::prelude::Vec3;

    #[test]
    fn ramp_top_surface_runs_from_the_floor_to_the_deck() {
        let specs = [
            RampSpec {
                angle_degrees: 20.0,
                low_x: 8.0,
                z: 15.0,
                width: 3.0,
                run: 4.0,
            },
            RampSpec {
                angle_degrees: 40.0,
                low_x: 8.0,
                z: 11.0,
                width: 3.0,
                run: 3.0,
            },
            RampSpec {
                angle_degrees: 50.0,
                low_x: 8.0,
                z: 7.0,
                width: 3.0,
                run: 2.0,
            },
        ];

        for spec in specs {
            let size = spec.slab_size();
            let half = size * 0.5;
            let center = spec.slab_center();
            let rotation = spec.rotation();

            let low = center + rotation * Vec3::new(-half.x, half.y, 0.0);
            let high = center + rotation * Vec3::new(half.x, half.y, 0.0);

            assert!(low.y.abs() < 0.0001);
            assert!((low.x - spec.low_x).abs() < 0.0001);
            assert!((high.y - spec.height()).abs() < 0.0001);
            assert!((high.x - (spec.low_x + spec.run)).abs() < 0.0001);
            assert!((size.y - RAMP_THICKNESS).abs() < 0.0001);
        }
    }
}
