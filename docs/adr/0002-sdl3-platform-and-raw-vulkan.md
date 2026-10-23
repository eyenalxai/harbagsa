# SDL3 platform and raw Vulkan renderer

The engine uses SDL3 for the window, input, cursor capture, and Vulkan surface. The renderer is raw Vulkan, not SDL_GPU. SDL3 covers the audio, gamepad, and dialog needs that arrive later, so the engine avoids a second platform layer. Raw Vulkan keeps the renderer under our control and matches the Linux + Vulkan target. SDL_GPU would hide the API and add a second renderer abstraction. The platform seam is small, so a later swap is possible; the renderer is the larger commitment. FSR4 is out of scope, so the renderer does not reserve temporal inputs yet.

## Considered Options

- **GLFW + raw Vulkan**: the smallest first slice, but audio and gamepad need extra libraries.
- **SDL3 GPU**: the fastest path to pixels, but it hides the Vulkan API.
