#version 460

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_color;
layout(location = 2) in vec3 v_world_position;
layout(location = 3) in vec3 v_local_position;

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_velocity;

struct ObjectData {
    mat4 model;
    mat4 prev_model;
    vec4 color;
};

layout(push_constant) uniform PushConstants {
    uint object_index;
} draw;

layout(set = 0, binding = 2) readonly buffer Objects {
    ObjectData objects[];
} scene;

#include "camera.glsl"

layout(set = 0, binding = 1) uniform sampler2DShadow shadow_map;

const vec3 SUN_COLOR = vec3(1.0, 0.98, 0.94);
const float SHADOW_NORMAL_OFFSET = 0.04;
const float SHADOW_DEPTH_BIAS = 0.0006;

float sun_visibility(vec3 world_position, vec3 normal, vec3 to_light) {
    vec4 light_position = camera.light_view_projection *
        vec4(world_position + normal * SHADOW_NORMAL_OFFSET, 1.0);
    vec3 projected = light_position.xyz / light_position.w;
    vec3 uv = projected * 0.5 + 0.5;
    if (any(lessThan(uv, vec3(0.0))) || any(greaterThan(uv, vec3(1.0)))) {
        return 1.0;
    }

    float bias = max(SHADOW_DEPTH_BIAS, 0.003 * (1.0 - dot(normal, to_light)));
    vec2 texel = 1.0 / vec2(textureSize(shadow_map, 0));
    float visibility = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            visibility += texture(
                shadow_map,
                vec3(uv.xy + vec2(x, y) * texel, projected.z - bias)
            );
        }
    }
    return visibility / 9.0;
}

void main() {
    ObjectData object = scene.objects[draw.object_index];

    vec3 normal = normalize(v_normal);
    vec3 to_light = normalize(-camera.light_direction.xyz);
    float diffuse = max(dot(normal, to_light), 0.0);
    float visibility = sun_visibility(v_world_position, normal, to_light);
    vec3 color = v_color * (camera.ambient.rgb + diffuse * SUN_COLOR * visibility);

    vec4 world_position = vec4(v_world_position, 1.0);
    vec4 previous_world = object.prev_model * vec4(v_local_position, 1.0);
    vec4 previous_clip = camera.prev_view_projection * previous_world;
    vec2 previous_uv = vec2(2.0);
    if (previous_clip.w > 0.0) {
        previous_uv = (previous_clip.xy / previous_clip.w) * 0.5 + 0.5;
    }
    vec2 pixel_uv = gl_FragCoord.xy / camera.screen.yz;
    float view_depth = -(camera.view * world_position).z;

    out_color = vec4(color, 1.0);
    out_velocity = vec4(previous_uv - pixel_uv, view_depth, 0.0);
}
