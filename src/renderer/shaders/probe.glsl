#ifndef PROBE_GLSL
#define PROBE_GLSL

// The Odin mirror is in src/renderer/probe.odin. Change both together.
#define PROBE_GRID_SIZE 8
#define PROBE_TEXELS 64
#define PROBE_RAYS 256
#define PROBE_IRRADIANCE_ENCODING_GAMMA 5.0
#define PROBE_DISTANCE_EXPONENT 50.0
#define PROBE_HYSTERESIS 0.75
#define PROBE_LARGE_CHANGE_THRESHOLD 0.25
#define PROBE_VISIBILITY_BIAS 0.05
#define PROBE_VISIBILITY_MIN_BIAS 0.05
#define PROBE_PI 3.14159265358979
// The reference gather returns irradiance. The lit pass adds the sun as
// albedo * NdotL, so the diffuse BRDF's 1/pi keeps both terms on one scale.
#define PROBE_INDIRECT_SCALE (1.0 / PROBE_PI)

vec2 oct_wrap(vec2 value) {
    return (1.0 - abs(value.yx)) * vec2(
        value.x >= 0.0 ? 1.0 : -1.0,
        value.y >= 0.0 ? 1.0 : -1.0
    );
}

// Unit vector to the [0, 1] octahedral square.
vec2 oct_encode(vec3 direction) {
    direction /= abs(direction.x) + abs(direction.y) + abs(direction.z);
    if (direction.y < 0.0) {
        direction.xz = oct_wrap(direction.xz);
    }
    return direction.xz * 0.5 + 0.5;
}

vec3 oct_decode(vec2 uv) {
    vec2 value = uv * 2.0 - 1.0;
    vec3 direction = vec3(value.x, 1.0 - abs(value.x) - abs(value.y), value.y);
    if (direction.y < 0.0) {
        direction.xz = oct_wrap(direction.xz);
    }
    return normalize(direction);
}

// A fixed spherical Fibonacci set. The ray and blend passes derive the same
// direction from the ray index, so the ray buffer stores no directions.
vec3 probe_ray_direction(uint index) {
    float i = float(index) + 0.5;
    float count = float(PROBE_RAYS);
    float z = 1.0 - 2.0 * i / count;
    float radius = sqrt(max(0.0, 1.0 - z * z));
    float angle = i * 2.39996323;
    return vec3(radius * cos(angle), z, radius * sin(angle));
}

#endif
