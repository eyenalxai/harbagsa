use bevy::prelude::*;
use bevy_rapier3d::prelude::Collider;

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

fn spawn_arena(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let floor_material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.16, 0.17, 0.20),
        perceptual_roughness: 0.95,
        ..default()
    });
    let wall_material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.09, 0.10, 0.12),
        perceptual_roughness: 0.90,
        ..default()
    });

    spawn_box(
        &mut commands,
        &mut meshes,
        &floor_material,
        Vec3::new(0.0, -0.5, 0.0),
        Vec3::new(40.0, 1.0, 40.0),
    );

    let wall_size = Vec3::new(41.0, 4.0, 1.0);
    let side_wall_size = Vec3::new(1.0, 4.0, 41.0);
    for z in [-20.5, 20.5] {
        spawn_box(
            &mut commands,
            &mut meshes,
            &wall_material,
            Vec3::new(0.0, 2.0, z),
            wall_size,
        );
    }
    for x in [-20.5, 20.5] {
        spawn_box(
            &mut commands,
            &mut meshes,
            &wall_material,
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

    commands.insert_resource(GlobalAmbientLight {
        color: Color::srgb(0.55, 0.65, 0.80),
        brightness: 200.0,
        ..default()
    });
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
