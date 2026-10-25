#ifndef PROBE_GLSL
#define PROBE_GLSL

// The Odin mirror is in src/renderer/probe.odin. Change both together.
#define PROBE_GRID_SIZE 8
#define PROBE_TEXELS 64
#define PROBE_RAYS 64
#define PROBE_BOUNCE_ALPHA 0.25
#define PROBE_INDIRECT_SCALE 1.0

vec2 oct_wrap(vec2 value) {
    return (1.0 - abs(value.yx)) * vec2(
        value.x >= 0.0 ? 1.0 : -1.0,
        value.y >= 0.0 ? 1.0 : -1.0
    );
}

// Unit vector to the [-1, 1] octahedral square. The square is mapped to [0, 1]
// for texel lookup.
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

#endif
