// Shared by the sky pass and the probe rays. The sky is an art-directed
// gradient, not a physical atmosphere. It fills the background and it is the
// environment a probe ray sees when it escapes the scene.

const vec3 SKY_ZENITH = vec3(0.10, 0.20, 0.42);
const vec3 SKY_HORIZON = vec3(0.52, 0.62, 0.74);
const vec3 SKY_GROUND = vec3(0.16, 0.17, 0.18);

vec3 sky_gradient(vec3 direction) {
    float up = clamp(direction.y, 0.0, 1.0);
    vec3 above = mix(SKY_HORIZON, SKY_ZENITH, pow(up, 0.45));
    float below = clamp(-direction.y * 4.0, 0.0, 1.0);
    return mix(above, SKY_GROUND, below);
}
