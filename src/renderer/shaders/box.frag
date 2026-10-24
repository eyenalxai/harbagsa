#version 460
#extension GL_EXT_ray_query : require

layout(early_fragment_tests) in;

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

layout(set = 0, binding = 1) readonly buffer Objects {
    ObjectData objects[];
} scene;

#include "camera.glsl"
#include "sky.glsl"

layout(set = 0, binding = 2) uniform accelerationStructureEXT scene_tlas;

// std430: position.xyz is the light position and position.w its intensity;
// color.rgb is the light color and color.w its range.
struct Light {
    vec4 position;
    vec4 color;
};

layout(set = 0, binding = 3) readonly buffer Lights {
    Light lights[];
} light_set;

const vec3 SUN_COLOR = vec3(1.0, 0.98, 0.94);
const int SUN_SAMPLES = 16;
const float GOLDEN_ANGLE = 2.39996323;
const uint SUN_RAY_MASK = 0xFFu;
// A lamp instance carries 0x01. The point shadow ray tests 0x02, so a lamp
// never blocks its own light while the sun ray still sees it.
const uint POINT_RAY_MASK = 0x02u;

vec2 vogel_disk(int index, int count, float phase) {
    float radius = sqrt((float(index) + 0.5) / float(count));
    float angle = float(index) * GOLDEN_ANGLE + phase;
    return radius * vec2(cos(angle), sin(angle));
}

float interleaved_gradient_noise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

vec3 sun_direction(vec3 to_light, int index, int count, float phase) {
    vec3 up = abs(to_light.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, to_light));
    vec3 bitangent = cross(to_light, tangent);
    vec2 disk = vogel_disk(index, count, phase) * camera.sun.x;
    return normalize(to_light + tangent * disk.x + bitangent * disk.y);
}

bool occluded(vec3 origin, vec3 direction, uint mask) {
    rayQueryEXT query;
    rayQueryInitializeEXT(
        query,
        scene_tlas,
        gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT,
        mask,
        origin,
        0.001,
        direction,
        max_distance
    );
    while (rayQueryProceedEXT(query)) {}
    return rayQueryGetIntersectionTypeEXT(query, true) != gl_RayQueryCommittedIntersectionNoneEXT;
}

float sun_visibility(vec3 world_position, vec3 normal, vec3 to_light) {
    vec3 origin = world_position + normal * 0.002;
    float phase = fract(
        interleaved_gradient_noise(gl_FragCoord.xy) + camera.screen.w * 0.61803398875
    ) * 6.2831853;

    int visible = 0;
    for (int i = 0; i < SUN_SAMPLES; ++i) {
        vec3 direction = sun_direction(to_light, i, SUN_SAMPLES, phase);
        if (!occluded(origin, direction, SUN_RAY_MASK)) {
            visible += 1;
        }
    }
    return float(visible) / float(SUN_SAMPLES);
}

vec3 point_light_radiance(vec3 world_position, vec3 normal) {
    int count = int(camera.sun.y);
    bool shadows = camera.sun.z > 0.5;
    vec3 sum = vec3(0.0);
    for (int i = 0; i < count; ++i) {
        Light light = light_set.lights[i];
        vec3 offset = light.position.xyz - world_position;
        float distance = length(offset);
        if (distance <= 0.0 || distance >= light.color.w) {
            continue;
        }
        vec3 direction = offset / distance;
        float diffuse = max(dot(normal, direction), 0.0);
        if (diffuse <= 0.0) {
            continue;
        }
        float reach = distance / light.color.w;
        float falloff = 1.0 - reach * reach;
        falloff *= falloff;
        float visibility = 1.0;
        if (shadows && occluded(world_position + normal * 0.002, direction, POINT_RAY_MASK)) {
            visibility = 0.0;
        }
        sum += light.color.rgb * (light.position.w * diffuse * falloff * visibility);
    }
    return sum;
}

void main() {
    ObjectData object = scene.objects[draw.object_index];

    vec3 normal = normalize(v_normal);
    vec3 to_light = normalize(-camera.light_direction.xyz);
    float diffuse = max(dot(normal, to_light), 0.0);
    float visibility = 0.0;
    if (diffuse > 0.0) {
        visibility = sun_visibility(v_world_position, normal, to_light);
    }
    vec3 lit = camera.ambient.rgb + diffuse * SUN_COLOR * visibility;
    lit += point_light_radiance(v_world_position, normal);
    vec3 color = v_color * lit + v_color * object.color.a;

    vec4 world_position = vec4(v_world_position, 1.0);
    vec4 previous_world = object.prev_model * vec4(v_local_position, 1.0);
    vec4 previous_clip = camera.prev_view_projection * previous_world;
    vec2 previous_uv = vec2(2.0);
    if (previous_clip.w > 0.0) {
        previous_uv = (previous_clip.xy / previous_clip.w) * 0.5 + 0.5;
    }
    // The vertex shader jitters the clip position. The velocity target needs
    // unjittered screen motion, so project the current world point with the
    // unjittered current view-projection.
    vec2 current_uv = vec2(2.0);
    vec4 current_clip = camera.projection * camera.view * world_position;
    if (current_clip.w > 0.0) {
        current_uv = (current_clip.xy / current_clip.w) * 0.5 + 0.5;
    }
    float view_depth = -(camera.view * world_position).z;

    out_color = vec4(color, 1.0);
    out_velocity = vec4(previous_uv - current_uv, view_depth, 0.0);
}
