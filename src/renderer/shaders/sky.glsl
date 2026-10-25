// Shared by the sky pass. The sky is an art-directed gradient, not a physical
// atmosphere, and it is a background rather than a light.

const vec3 SKY_ZENITH = vec3(0.10, 0.20, 0.42);
const vec3 SKY_HORIZON = vec3(0.52, 0.62, 0.74);
const vec3 SKY_GROUND = vec3(0.16, 0.17, 0.18);
const vec3 SKY_SUN_COLOR = vec3(1.0, 0.97, 0.90);
const vec3 SKY_GLOW_COLOR = vec3(1.0, 0.86, 0.66);

vec3 sky_gradient(vec3 direction) {
    float up = clamp(direction.y, 0.0, 1.0);
    vec3 above = mix(SKY_HORIZON, SKY_ZENITH, pow(up, 0.45));
    float below = clamp(-direction.y * 4.0, 0.0, 1.0);
    return mix(above, SKY_GROUND, below);
}

// The disk uses the same angular radius as the sun samples, so the visible sun
// and the penumbra on the ground agree. The value is art-directed: it clips to
// white so the disk reads as the sun without a tonemap.
vec3 sky_color(vec3 direction, vec3 sun_direction, float sun_tangent) {
    vec3 color = sky_gradient(direction);
    float cosine = clamp(dot(direction, sun_direction), -1.0, 1.0);
    float angle = acos(cosine);
    float disk = 1.0 - smoothstep(sun_tangent * 0.85, sun_tangent * 1.15, angle);
    float glow = pow(max(cosine, 0.0), 512.0) * 0.9 + pow(max(cosine, 0.0), 24.0) * 0.10;
    return color + SKY_SUN_COLOR * (disk * 12.0) + SKY_GLOW_COLOR * glow;
}
