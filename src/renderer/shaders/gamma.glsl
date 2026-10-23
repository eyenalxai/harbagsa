// sRGB swapchains encode the fragment output in hardware. Other formats need
// an explicit gamma step so colors match the sRGB path.
vec3 apply_gamma(vec3 color, float needs_gamma) {
    if (needs_gamma > 0.5) {
        return pow(color, vec3(1.0 / 2.2));
    }
    return color;
}
