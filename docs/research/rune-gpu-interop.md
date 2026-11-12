# Handing Rune's rendered frame to an external Vulkan renderer

**Date:** 2026-11-10
**Status:** Code-read research note. No build, no Vulkan run, no validation layer, no pixel comparison. Sources: `rune` at commit `f18ead8` (2026-11-10); `wgpu` 30.0.1 and its `wgpu-core`/`wgpu-hal`/`wgpu-types` 30.0.1 siblings from the local cargo registry; the Vulkan specification and extension reference pages where the local source does not answer.
**Question:** Can Rune draw its UI with its own renderer and hand the result to the game's raw-Vulkan 1.3 renderer at 60 fps, with no CPU readback and no second window?
**Short answer:** Yes, but not through any safe `wgpu` API. `wgpu` 30.0.1 exposes a public `unsafe` interop layer in `wgpu-hal` that can adopt the game's `VkInstance`, `VkPhysicalDevice`, `VkDevice` and queue, and can wrap a `VkImage` the game owns as a `wgpu::Texture`. Rune's renderer already needs nothing but a device, a queue and a `TextureView` — its headless path draws into a texture it owns with no window. The zero-copy route therefore exists: Rune draws into the game's image, the game composites it in its own pass. What is missing is glue, not capability: the game must create its instance and device to wgpu's specification, Rune needs a Vulkan interop host module it does not have, and someone must write a Rust `cdylib` shim because Rune has no C ABI. The fallback (render offscreen, read back, upload) also fits in a 60 fps budget at 1080p but costs 1-2 ms per frame and 1-3 frames of latency.

## Answer

The consumer is an Odin program with a raw Vulkan 1.3 renderer and its own swapchain. Rune is Rust. Two independent facts decide the answer:

1. **`wgpu` cannot be given a `VkImage` from another device.** `wgpu::Device::create_texture_from_hal` requires the hal texture to have been created from *this* device's internal handle (`wgpu-30.0.1/src/api/device.rs:335-340`), and `wgpu_hal::vulkan::Device::texture_from_raw` requires the `vk_image` to be created respecting `desc` and, unless a drop callback is supplied, takes ownership (`wgpu-hal-30.0.1/src/vulkan/device.rs:285-300`). So the game and Rune must share one `VkDevice`, or the image must cross devices as a dma-buf (which wgpu can import but not export).

2. **`wgpu` 30.0.1 does expose the adoption path.** `wgpu_hal::vulkan::Instance::from_raw` takes an `ash::Instance` built from the game's `VkInstance` (`wgpu-hal-30.0.1/src/vulkan/instance.rs:306-320`), `wgpu::Instance::from_hal` lifts that into wgpu (`wgpu-30.0.1/src/api/instance.rs:326-340`), `wgpu_hal::vulkan::Adapter::device_from_raw` takes an `ash::Device` built from the game's `VkDevice` (`wgpu-hal-30.0.1/src/vulkan/adapter.rs:2562-2580`), and `wgpu::Adapter::create_device_from_hal` turns the resulting `OpenDevice` into a `wgpu::Device`/`wgpu::Queue` (`wgpu-30.0.1/src/api/adapter.rs:70-97`). All are `pub unsafe`, all are gated only on the `wgpu_core` cfg, which wgpu's own build script says is always on for native builds (`wgpu-30.0.1/build.rs:38-45`).

So the answer is yes: **Rune renders into a `VkImage` the game owns, on the game's `VkDevice`, and the game samples that image in its own pass.** Nothing is copied to the CPU, nothing is presented by Rune, and the window and swapchain stay the game's. The per-frame cost is Rune's own UI draw plus one textured, alpha-blended quad over the UI rectangle in the game's render pass.

What this answer is *not*:

- It is not reachable from `wgpu`'s safe API. There is no safe `Instance::from_vk_instance`, no safe `Device::from_vk_device`, no `Texture` from a `VkImage`, and no `Surface` from a `VkSurfaceKHR`.
- It is not zero-effort. Four pieces of work are required: the game's device-creation contract, a Rune host module, a Rust shim with a C ABI, and a synchronization protocol.
- It is not the only route. The sibling note `docs/research/rune-paint-contract.md` covers the opposite architecture: Rune runs headless, the game reimplements Rune's paint contract in Odin. That route needs no `wgpu` interop at all but reimplements layers, blur, effects and atlas upload. The two notes answer different questions; do not mix their conclusions.

### What the game must do at startup

The order is forced, because wgpu must know the device's capabilities before the device exists:

1. Create the `VkInstance` with at least the extensions returned by `wgpu_hal::vulkan::Instance::desired_extensions(entry, api_version, flags)` (`wgpu-hal-30.0.1/src/vulkan/instance.rs:227-300`). `Instance::from_raw`'s safety note requires the caller's extension list to be a superset of that set (`instance.rs:300-315`).
2. Wrap the raw instance in `ash::Instance::load(&entry, raw_instance)` and call `wgpu_hal::vulkan::Instance::from_raw(..., drop_callback: Some(...))`. With a drop callback, wgpu-hal does not destroy the instance (`wgpu-hal-30.0.1/src/vulkan/instance.rs:859-875`), so the game keeps ownership.
3. `wgpu::Instance::from_hal::<wgpu::hal::api::Vulkan>(hal_instance)` then `instance.enumerate_adapters(Backends::VULKAN)` (`wgpu-30.0.1/src/api/instance.rs:145-157`), and pick the adapter whose `as_hal::<Vulkan>()` reports the game's `VkPhysicalDevice` (`wgpu-hal-30.0.1/src/vulkan/adapter.rs:2500-2502`).
4. Ask that adapter for the device contract: `required_device_extensions(features)` (`adapter.rs:2516-2531`) and `physical_device_features(&extensions, features)` (`adapter.rs:2547-2560`). Create the game's `VkDevice` with those extensions and that feature chain, on a queue family whose queue was created with `flags = 0` (Vulkan valid usage `VUID-vkGetDeviceQueue-flags-01841`; wgpu retrieves the queue with `vkGetDeviceQueue`, `adapter.rs:2888-2891`).
5. `adapter.as_hal::<Vulkan>()` → `device_from_raw(raw_device, drop_callback, &extensions, features, &limits, &memory_hints, family_index, queue_index)` → `adapter.create_device_from_hal(open_device, &DeviceDescriptor)`. The `features`, `limits` and `memory_hints` passed to `device_from_raw` must be the same ones in the `DeviceDescriptor`, because the first builds the hal device's internal state and the second is checked against it (`wgpu-30.0.1/src/api/adapter.rs:70-76`).

Step 4 is the invasive one: the game's `VkDevice` is no longer the game's own. It is a wgpu-shaped device. Everything the game already does on it still works, but the device create info now carries wgpu's extension list (which unconditionally includes `VK_KHR_swapchain`, `wgpu-hal-30.0.1/src/vulkan/adapter.rs:1225`) and wgpu's feature set.

### What Rune needs

Rune's renderer is already surface-agnostic:

- `Gpu::try_new(instance, surface: Option<&wgpu::Surface>)` takes an optional surface (`crates/rune/src/render.rs:403-411`), so a surface is not required.
- The per-frame target is a `&wgpu::TextureView` in `Frame` (`crates/rune/src/compose.rs:65-84`, field `target` at line 70 with the comment "The window surface or the offscreen target").
- `Renderer::draw(encoder, view, clear)` renders into whatever view it is given (`crates/rune/src/render.rs:959-977`), and `Renderer::new(device, format)` fixes the target format (`render.rs:762`).
- The headless tooling already runs this with no window: `Gpu::try_with_features(instance, None, features)` followed by `Offscreen::with_format` and `renderer.draw(&mut enc, view, ...)` (`crates/rune/src/tooling/headless.rs:145-147, 363`).

So Rune needs no new renderer. It needs a host module shaped like `platform::embed::LayerHost` (`crates/rune/src/platform/embed.rs:52-119`) that (a) takes a `wgpu::TextureView` supplied by the caller instead of acquiring a surface texture, and (b) is compiled on Linux. Today the only host-embed path is Apple-only: `platform::embed` is `#[cfg(target_vendor = "apple")]` (`crates/rune/src/platform.rs:7-8`), and its doc comment says "Embedded `CAMetalLayer` host for UIKit, SwiftUI and AppKit" (`embed.rs:1-2`). Rune already has the wrapping code shape on other platforms — `native_surface/macos.rs:283` and `native_surface/windows.rs:105-140` import foreign textures through `create_texture_from_hal` — but `native_surface` is compiled only for macOS and Windows (`native_surface/mod.rs:1-13`); there is no Vulkan variant.

### What the shim needs

Rune publishes no C ABI: no `crate-type = ["cdylib"]` or `["staticlib"]` and no `extern "C"` export surface in `crates/rune` (the only `cdylib` crates are web examples and `www/app`). An Odin host therefore needs a small Rust crate that owns the adopted `wgpu::Instance`/`Device`/`Queue`, the `Runtime`, the `Renderer` and the wrapped textures, and exposes a C ABI of roughly ten functions (`init`, `resize`, `frame`, `pointer`, `key`, `text`, `shutdown`, …). The UI itself is written in Rust against Rune's API, or in Luau through `crates/rune-luau`, which builds `rune::El`s from scripts (`crates/rune-luau/src/lib.rs:1-25`).

## Evidence

All Rune line references are from `f18ead8`. All wgpu references are from the 30.0.1 sources named in **Versions and source paths**.

### 1. Adopting an existing `VkInstance`, `VkPhysicalDevice`, `VkDevice`, `VkQueue`

#### 1.1 Public and safe

Nothing that adopts a Vulkan object.

- `wgpu::InstanceDescriptor` has exactly five fields: `backends`, `flags`, `memory_budget_thresholds`, `backend_options`, `display` (`wgpu-types-30.0.1/src/instance.rs:27-62`). No field takes a `VkInstance` or a loader dispatch.
- `wgpu::Instance::new(descriptor)` creates its own instance; `wgpu::Instance::create_surface`/`create_surface_unsafe` take a window handle, not a `VkSurfaceKHR` (`wgpu-30.0.1/src/api/instance.rs:184, 271`).
- `wgpu::Adapter::request_device` creates a device; there is no safe `Device::from_vk_device`.

#### 1.2 Public but `unsafe`

All of these are `pub unsafe fn`, and all are `#[cfg(wgpu_core)]`. wgpu's build script says `wgpu_core` is "currently always enabled" on native targets (`wgpu-30.0.1/build.rs:38-45`), and Rune enables wgpu's `vulkan` feature on Linux (`crates/rune/Cargo.toml:190-191`), so they exist in Rune's build.

| Item | Signature / effect | Source |
|---|---|---|
| `wgpu_hal::vulkan::Instance::from_raw` | `(entry, raw_instance: ash::Instance, instance_api_version, android_sdk_version, debug_utils_create_info, extensions, flags, memory_budget_thresholds, has_nv_optimus, drop_callback)`. The only way to hand wgpu an existing `VkInstance`. | `wgpu-hal-30.0.1/src/vulkan/instance.rs:317-330` |
| `wgpu::Instance::from_hal::<A>` | Lifts a `wgpu_hal` instance into wgpu. Takes `A::Instance`, not an `ash::Instance`. | `wgpu-30.0.1/src/api/instance.rs:335-340` |
| `wgpu::Instance::as_hal::<A>` | `Option<&A::Instance>` | `wgpu-30.0.1/src/api/instance.rs:372-377` |
| `wgpu::Instance::create_adapter_from_hal` | Wraps a `hal::ExposedAdapter` as a `wgpu::Adapter`. | `wgpu-30.0.1/src/api/instance.rs:392-400` |
| `wgpu_hal::vulkan::Adapter::raw_physical_device` | `vk::PhysicalDevice` of the adapter. | `wgpu-hal-30.0.1/src/vulkan/adapter.rs:2500-2502` |
| `wgpu_hal::vulkan::Adapter::required_device_extensions` | The extensions the game's `VkDevice` must enable. | `wgpu-hal-30.0.1/src/vulkan/adapter.rs:2516-2531` |
| `wgpu_hal::vulkan::Adapter::physical_device_features` | The `VkPhysicalDeviceFeatures` (plus pNext chain) the game's device must enable. | `wgpu-hal-30.0.1/src/vulkan/adapter.rs:2547-2560` |
| `wgpu_hal::vulkan::Adapter::device_from_raw` | `(raw_device, drop_callback, extensions, features, limits, memory_hints, family_index, queue_index) -> OpenDevice`. Retrieves the queue with `vkGetDeviceQueue`. | `wgpu-hal-30.0.1/src/vulkan/adapter.rs:2570-2585`, queue at `2888-2891` |
| `wgpu::Adapter::create_device_from_hal` | `(hal::OpenDevice<A>, &DeviceDescriptor) -> (Device, Queue)` | `wgpu-30.0.1/src/api/adapter.rs:77-97` |
| `wgpu::Adapter::as_hal::<A>` | `Option<impl Deref<Target = A::Adapter>>` | `wgpu-30.0.1/src/api/adapter.rs:99-136` |
| `wgpu::Device::as_hal::<A>` | `Option<impl Deref<Target = A::Device>>` | `wgpu-30.0.1/src/api/device.rs:668-676` |
| `wgpu::Queue::as_hal::<A>` | `Option<impl Deref<Target = A::Queue>>` | `wgpu-30.0.1/src/api/queue.rs:360-367` |
| `wgpu::Device::create_texture_from_hal` | `(hal_texture, &TextureDescriptor, initial_state) -> Texture` | `wgpu-30.0.1/src/api/device.rs:341-365` |
| `wgpu::Device::create_buffer_from_hal` | Same for buffers. | `wgpu-30.0.1/src/api/device.rs:463-480` |
| `wgpu::Texture::as_hal::<A>` | Guard to the hal texture. | `wgpu-30.0.1/src/api/texture.rs:62-66` |
| `wgpu::CommandEncoder::as_hal_mut` / `transition_resources` | Raw encoder access; explicit texture-state transitions. | `wgpu-30.0.1/src/api/command_encoder.rs:277-289, 431-450` |
| `wgpu::hal` | `pub extern crate wgpu_hal as hal;` — the whole hal tree is reachable without a direct `wgpu-hal` dependency. | `wgpu-30.0.1/src/lib.rs:249` |

Two more public hal methods matter for synchronization and for getting handles back out:

- `wgpu_hal::vulkan::Queue::as_raw() -> vk::Queue` (`wgpu-hal-30.0.1/src/vulkan/mod.rs:676-678`), plus `add_signal_semaphore` / `add_wait_semaphore` / `remove_*` (`mod.rs:1524-1565`), which stage raw `VkSemaphore`s (binary or timeline) onto the next wgpu submit.
- `wgpu_hal::vulkan::Texture::{raw_handle, memory}` (`mod.rs:831-846`), which return the raw `vk::Image` and its `TextureMemory`.

#### 1.3 Does not exist

| Missing | Evidence |
|---|---|
| A `wgpu::InstanceDescriptor` field for an existing `VkInstance` | `wgpu-types-30.0.1/src/instance.rs:43-61` |
| Any safe `from_vk_instance` / `from_vk_device` / `from_vk_image` | grep of `wgpu-30.0.1/src`, `wgpu-hal-30.0.1/src`: only `ash`-typed hal constructors |
| A `wgpu::Surface` from a `VkSurfaceKHR` | `wgpu_hal::vulkan::Instance::create_surface_from_vk_surface_khr` is `pub(super)` (`wgpu-hal-30.0.1/src/vulkan/instance.rs:548-558`); the only public entry points take `RawWindowHandle`/`RawDisplayHandle` (`wgpu-30.0.1/src/api/instance.rs:271`) |
| A way to pass a `VkQueue` handle directly | `device_from_raw` takes `family_index`/`queue_index` and calls `vkGetDeviceQueue` (`adapter.rs:2888-2891`) |
| External-memory export | no `VkExportMemoryAllocateInfo`, no `vkGetMemoryFdKHR`, no `vkGetMemoryWin32HandleKHR` anywhere in `wgpu`/`wgpu-core`/`wgpu-hal`; the only external-memory call is `vkGetMemoryFdPropertiesKHR` on the *import* path (`wgpu-hal-30.0.1/src/vulkan/device.rs:611-680`) |
| External-semaphore import/export | no `external_semaphore` / `VkSemaphoreGetFdInfoKHR` / `VkImportSemaphoreFdInfoKHR` in any of the three crates. Raw semaphores can only be injected through the hal queue lists (`mod.rs:1524-1565`) |
| A surface-free `wgpu::Instance` that wraps a `VkSurfaceKHR` | as above |

#### 1.4 The adoption handshake, in order

```text
game: vkCreateInstance   (extensions ⊇ Instance::desired_extensions)
      ash::Instance::load(entry, raw_instance)
      wgpu_hal::vulkan::Instance::from_raw(..., drop_callback = Some)      // unsafe
      wgpu::Instance::from_hal::<Vulkan>(hal_instance)                     // unsafe
      instance.enumerate_adapters(VULKAN)                                  // safe
      adapter.as_hal::<Vulkan>()                                           // unsafe
        -> required_device_extensions(features)
        -> physical_device_features(&extensions, features)
game: vkCreateDevice     (extensions, feature chain, queue family, flags = 0)
      ash::Device::load(&instance, raw_device)
      hal_adapter.device_from_raw(raw_device, Some(cb), &extensions,
                                  features, &limits, &hints, family, index) // unsafe
      adapter.create_device_from_hal(open_device, &DeviceDescriptor)       // unsafe
game: vkCreateImage      (format, usage, tiling, sharing)
      hal_device.texture_from_raw(vk_image, &hal_desc, Some(cb),
                                  TextureMemory::External)                 // unsafe
      device.create_texture_from_hal(hal_texture, &webgpu_desc,
                                     initial_state)                        // unsafe
```

`ash::Instance::load` and `ash::Device::load` are ordinary ash constructors; the Odin side only has to hand over the raw handles.

### 2. Rendering into an externally created `VkImage`

#### 2.1 The raw-image route requires one `VkDevice`

`wgpu::Device::create_texture_from_hal`'s safety contract says the hal texture "must be created from this device internal handle" (`wgpu-30.0.1/src/api/device.rs:335-339`), and it forwards to wgpu-core, which validates the descriptor and registers the hal texture in its tracker (`wgpu-core-30.0.1/src/device/resource.rs:1244-1262`). `wgpu_hal::vulkan::Device::texture_from_raw` stores the `vk::Image`, the `VkFormat` derived from `desc.format`, the copy extent, an identity and an optional drop guard (`wgpu-hal-30.0.1/src/vulkan/device.rs:296-320`). Nothing in that path re-derives anything from the image; `desc` is trusted.

Ownership is controllable. `TextureMemory::External` means wgpu never frees the memory (`wgpu-hal-30.0.1/src/vulkan/mod.rs:805-814`), and `destroy_texture` only calls `vkDestroyImage` when `drop_guard.is_none()` (`wgpu-hal-30.0.1/src/vulkan/device.rs:1231-1234`). Passing `drop_callback: Some(...)` therefore leaves both the image and its memory with the game, even if `Texture::destroy()` is called.

#### 2.2 External memory: import yes, export no

| Capability | Status at 30.0.1 | Source |
|---|---|---|
| `VK_KHR_external_memory` / `_fd` feature exposed | Yes, `Features::VULKAN_EXTERNAL_MEMORY_FD` | `wgpu-types-30.0.1/src/features.rs:1225-1233` |
| dma-buf feature exposed | Yes, `Features::VULKAN_EXTERNAL_MEMORY_DMA_BUF`, set only when `VK_KHR_external_memory_fd`, `VK_EXT_external_memory_dma_buf` and `VK_EXT_image_drm_format_modifier` are all supported | `features.rs:1235-1248`; `wgpu-hal-30.0.1/src/vulkan/adapter.rs:1059-1066` |
| Device extensions enabled when supported | `VK_KHR_external_memory_fd`, `VK_EXT_external_memory_dma_buf`, `VK_EXT_image_drm_format_modifier` | `adapter.rs:1344-1353` |
| Import a dma-buf as a texture | `texture_from_dmabuf_fd(fd, desc, drm_modifier, stride, offset)`; single-plane only; creates the `VkImage` itself with `DRM_FORMAT_MODIFIER_EXT` tiling and an explicit plane layout, then a dedicated-allocation import | `wgpu-hal-30.0.1/src/vulkan/device.rs:518-610` |
| Export a wgpu texture as a dma-buf | No. wgpu never sets `VkExportMemoryAllocateInfo`, which the spec requires before `vkGetMemoryFdKHR` is valid | spec: `VkExportMemoryAllocateInfo` ("When allocating memory whose payload may be exported … add a `VkExportMemoryAllocateInfo`") |
| Import an OPAQUE_FD / Win32 handle | Win32: `texture_from_d3d11_shared_handle` (Windows only). OPAQUE_FD: no dedicated path; only the dma-buf path exists on Unix | `device.rs:449-515` |

The asymmetry is the important part: **wgpu can consume a dma-buf, but cannot produce one.** Any two-device design has to make the game the producer.

#### 2.3 What breaks with the raw-image route

| Concern | What goes wrong | Where enforced |
|---|---|---|
| **Layout** | wgpu seeds its tracker with `initial_state` and emits the first barrier's `oldLayout` from it. A wrong state is a validation error or silent corruption. `TextureUses::COLOR_TARGET` maps to `COLOR_ATTACHMENT_OPTIMAL`; `RESOURCE` maps to `SHADER_READ_ONLY_OPTIMAL`. | `wgpu-30.0.1/src/api/device.rs:352-365`; mapping in `wgpu-hal-30.0.1/src/vulkan/conv.rs:247-249` |
| **Ownership** | `drop_callback: None` makes wgpu destroy the `VkImage`; `Some` leaves it. `TextureMemory::External` always leaves the memory. | `device.rs:285-300`, `1229-1248` |
| **Queue family** | wgpu's `TextureDescriptor` has no sharing mode. Images wgpu creates itself are `SharingMode::EXCLUSIVE` (`device.rs:400`). A wrapped image keeps whatever the game created, but wgpu emits no ownership transfers. Same family is the only simple case. | `wgpu-hal-30.0.1/src/vulkan/device.rs:395-401` |
| **Synchronization** | wgpu orders only its own submissions. `initial_state` gives the barrier the right `srcStage`/`srcAccess` for the *same-queue* handoff (`conv.rs:312-319`), but cross-queue or cross-device needs semaphores the safe API does not expose. | `conv.rs:300-330` |
| **Description fidelity** | `desc.format`, `size`, `mip_level_count`, `sample_count`, `dimension` are stored, not checked. `desc.view_formats` must be empty unless the image was created with `MUTABLE_FORMAT`. | `device.rs:292-295`, `375-393` |
| **Usage** | The image's `VkImageUsageFlags` must include what `desc.usage` claims (`COLOR_ATTACHMENT` for a render target, `SAMPLED` for sampling). wgpu trusts the caller. | `wgpu-30.0.1/src/api/device.rs:341-360`; `conv.rs:268-280` |
| **Lifetime** | The game must not destroy the image while any wgpu submission references it; wgpu's tracker cannot see the game's submissions. | implied by the `texture_from_raw` contract |

The clean protocol for a per-frame handoff is:

1. Wrap each game-owned image once, not per frame, with `initial_state` set to the layout the game leaves it in.
2. Each frame, Rune records into the image's view (`Renderer::draw`) and finishes its encoder with `CommandEncoder::transition_resources` to put the image back in the handoff state (`wgpu-30.0.1/src/api/command_encoder.rs:431-450`).
3. The game waits for Rune's submission (same queue: submit order plus its own barrier; different queue: a semaphore), then samples the image.
4. Next frame the layout is exactly what `initial_state` promised, so the cycle repeats with no re-wrap.

### 3. Cost of the fallback: offscreen render, read back, upload

The fallback is what Rune already does in headless mode: `Offscreen` owns an `Rgba8UnormSrgb` texture with `RENDER_ATTACHMENT | COPY_SRC` and a readback buffer (`crates/rune/src/render.rs:1020-1060`), `copy_to` records `copy_texture_to_buffer` (`render.rs:1067-1086`), `read` maps it and polls (`render.rs:1089-1100`). The game then uploads the bytes into its own texture.

Frame sizes and required bandwidth:

| Target | Pixels | Bytes (RGBA8) | MiB | One-way at 60 fps |
|---|---:|---:|---:|---:|
| 1280×720 | 921,600 | 3,686,400 | 3.52 | 221 MB/s |
| 1920×1080 | 2,073,600 | 8,294,400 | 7.91 | 498 MB/s |
| 2560×1440 | 3,686,400 | 14,745,600 | 14.06 | 885 MB/s |

Transfer time per direction, using effective PCIe rates measured on real hardware (secondary sources, see References):

| Target | 3.69 MB @ 12 GB/s | @ 25 GB/s | @ 52 GB/s | Round trip @ 25 GB/s |
|---|---:|---:|---:|---:|
| 1280×720 | 0.31 ms | 0.15 ms | 0.07 ms | 0.29 ms |
| 1920×1080 | 0.69 ms | 0.33 ms | 0.16 ms | 0.66 ms |
| 2560×1440 | 1.23 ms | 0.59 ms | 0.28 ms | 1.18 ms |

12 GB/s is a measured PCIe 3.0 x16 figure, 25 GB/s a measured 4.0 x16 figure, 52 GB/s a measured 5.0 x16 figure. The host used for this note negotiates 5.0 x16 (`/sys/bus/pci/devices/0000:08:00.0/current_link_speed` = 32.0 GT/s, width 16) on an AMD RX 9060 XT under RADV, so the 52 GB/s column is the relevant ceiling there.

Small transfers do not reach those rates: on a 5.0 x16 link a 1 MB transfer measured 18-32 GB/s, because latency and link ramp dominate. At 3.7-14.7 MB per frame the effective rate sits between the small-transfer and saturated figures.

Adding the fixed per-frame work — `vkCmdCopyImageToBuffer`, fence wait, `vkMapMemory`, one host memcpy out, one memcpy into the upload staging buffer, `vkCmdCopyBufferToImage` — the model gives:

| Target | Gen3 x16 | Gen4 x16 | Gen5 x16 | Share of 16.67 ms (Gen4) |
|---|---:|---:|---:|---:|
| 1280×720 | 1.0-1.6 ms | 0.7-1.2 ms | 0.5-0.9 ms | 4-7% |
| 1920×1080 | 1.8-2.6 ms | 1.1-1.9 ms | 0.7-1.2 ms | 7-11% |
| 2560×1440 | 2.9-3.9 ms | 1.6-2.7 ms | 1.0-1.6 ms | 10-16% |

The CPU side is not free either: two host copies of 8.3 MB at a realistic 10-20 GB/s single-thread memcpy cost 0.4-0.8 ms at 1080p and 0.7-1.5 ms at 1440p, on the thread that does the mapping.

So the fallback **does** fit a 60 fps budget, including 1440p on Gen4, but it is not free and it is not zero-latency. Its real cost is latency: unless the pipeline is at least two frames deep (render N, copy N-1, upload N-2), the fence wait serializes the GPU and the CPU. Two frames of depth means the UI lags the game by 33 ms, which is visible on a cursor or a hover. Single-buffer, it is worse: the wait blocks the render thread for the rest of the GPU's frame.

The fallback has one large mitigation: **Rune can idle.** If nothing animates, Rune draws nothing (`Compositor::animating`, `crates/rune/src/compose.rs:51-56`; `Runtime::wake_deadline`, used in `platform/embed.rs:217-220`), and the game keeps sampling the last texture. A static HUD costs zero copies on the frames it does not change. Only animated UI pays.

No first-party measurement of this exact path on Linux was available. The numbers above are a bandwidth model with stated assumptions plus the secondary PCIe measurements; they are not a benchmark.

### 4. GPU-to-GPU without sharing a device

The mechanism on Linux is dma-buf, carried by `VK_KHR_external_memory` (core 1.1), `VK_KHR_external_memory_fd`, `VK_EXT_external_memory_dma_buf`, and `VK_EXT_image_drm_format_modifier`. Vulkan requires:

- The exporting allocation to be created with `VkExportMemoryAllocateInfo::handleTypes` containing the handle type (spec: `VkExportMemoryAllocateInfo`).
- The image to be created with `VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT` (or `LINEAR`) and a modifier both sides support, because the importer needs a concrete layout (`VkImageDrmFormatModifierExplicitCreateInfoEXT`; wgpu's import passes `drm_modifier`, `stride`, `offset` and one plane).
- A dedicated allocation in practice; the Vulkan Guide's import example carries `VkMemoryDedicatedAllocateInfo`, and wgpu's import does the same (`wgpu-hal-30.0.1/src/vulkan/device.rs:611-680`).
- Synchronization via `VK_KHR_external_semaphore_fd` (opaque fd or sync fd). On the kernel side, implicit dma-buf fences can be turned into a sync_file, but Vulkan's explicit model is the semaphore.

What the spec allows across devices is genuinely awkward, and worth quoting because the two statements pull in opposite directions:

- `VkImportMemoryFdInfoKHR` valid usage: "The memory from which `fd` was exported **must** have been created on the same underlying physical device as `device`" (`VUID-VkImportMemoryFdInfoKHR-fd-00668`).
- The handle-type compatibility table lists `VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT` with "No restriction" on `driverUUID` and `deviceUUID`, then notes that "query mechanisms exist in the Vulkan API that prevent the import of incompatible dma-bufs (such as `vkGetMemoryFdPropertiesKHR`)". The import VUID `-fd-01520` defers to those per-handle-type rules.

Reading both: the general rule is same physical device, dma-buf is the escape hatch, and the driver decides through `vkGetMemoryFdPropertiesKHR`. In practice a dma-buf crosses between two `VkDevice`s on the *same* GPU (or an iGPU/dGPU pair where the allocation is system-memory-backed); it is not a general cross-GPU transport, and there is no portable Vulkan P2P path for images.

wgpu at 30.0.1 supports the *import* half only:

- `texture_from_dmabuf_fd` is public (`wgpu-hal-30.0.1/src/vulkan/device.rs:525`), gated on the `VULKAN_EXTERNAL_MEMORY_DMA_BUF` feature, which the app must request on its `DeviceDescriptor`. Rune does **not** request it today: `device_on` asks for `TIMESTAMP_QUERY | DUAL_SOURCE_BLENDING | wanted | free_features` only (`crates/rune/src/render.rs:471-480`).
- There is no export API, so the game must be the producer.
- There is no external-semaphore API in wgpu, but `wgpu_hal::vulkan::Queue::add_wait_semaphore` / `add_signal_semaphore` accept raw `VkSemaphore`s and stage them onto the next submit (`wgpu-hal-30.0.1/src/vulkan/mod.rs:1524-1565`). A shim can therefore create an exportable semaphore on the game's device, import it into Rune's device, and have wgpu signal it as part of the frame's submission. That is a hal-level escape hatch, not a wgpu feature.

So a cross-device, same-GPU, zero-copy handoff is *possible*: the game allocates an exportable, modifier-tiled image, exports the fd, Rune imports it with `texture_from_dmabuf_fd` and renders into it, signals an external semaphore, the game waits and samples. It is also the most fragile route in this note, for reasons in the table:

| Constraint | Why it hurts |
|---|---|
| Single-plane only | `texture_from_dmabuf_fd`'s doc says "Currently only supports single-plane DMA-bufs" (`device.rs:518-520`) |
| Modifier negotiation | Both sides must pick a modifier the format and usage support; a mismatch imports successfully and samples garbage |
| Render-target support | `desc.usage` must be supported by the modifier; `create_image_without_memory_with_tiling` does not set `IMAGE_CREATE_EXTENDED_USAGE`, so a render target has to be a color-attachment-capable modifier for that format | 
| LINEAR is the portable choice | and linear render targets are slow or unsupported on some drivers |
| Two devices, two trackers | Layout, ownership and semaphore state are entirely the app's |
| Rune must opt in | `VULKAN_EXTERNAL_MEMORY_DMA_BUF` has to be added to Rune's device request |

### 5. Alternative architectures

#### 5.1 A second transparent window / overlay

Rune ships this today. `overlay.rs` documents the platform matrix: Wayland layer-shell with output-local input regions and a private seat queue; without layer-shell (GNOME) an XWayland override-redirect ARGB window with an empty input shape; X11 an override-redirect notification window; macOS a non-activating `NSPanel`; Windows a topmost tool window with `WS_EX_NOACTIVATE` (`crates/rune/src/overlay.rs:1-20`). Surfaces are created per overlay (`crates/rune/src/overlay/surface.rs:17-70`).

- **Platform/compositor needed:** Wayland needs `wlr-layer-shell`; GNOME does not have it, so the overlay falls back to XWayland (`overlay.rs:1-20`). X11 needs a compositing manager for real transparency. Windows needs DirectComposition for translucent pixels (`overlay/surface.rs:118-125`).
- **Input/focus:** an overlay can be click-through (empty input region / `WS_EX_TRANSPARENT`), and it never takes keyboard focus unless explicitly asked. That is good for a HUD and fatal for an in-window UI: a text field cannot be typed into without a non-activating keyboard policy, and a Wayland toplevel cannot be positioned at global coordinates relative to another window, so an overlay cannot track the game window's position or size.
- **Frame coherence:** two surfaces present independently through the compositor. There is no guarantee the UI lands in the same refresh as the 3D. A HUD is fine; UI that must sit on top of moving 3D will tear or lag by a compositor frame.
- **Verdict:** works, low effort, wrong shape for in-window UI.

#### 5.2 A subprocess with a shared texture

Same dma-buf and semaphore machinery as §4, plus a process boundary: `SCM_RIGHTS` fd passing over a Unix socket, handle lifetime across processes, crash handling, and input forwarding (Rune's `Runtime` takes pointer/key/text events; a subprocess would need them serialized). Every cost of §4 plus IPC. No benefit over in-process. **Reject.**

#### 5.3 Rune's renderer as the game's only renderer

Rune's `Compositor` trait hands the host `device`, `queue`, `encoder`, `target`, `format`, `size`, `dt` and the renderer, and runs at each effect slot in painter order (`crates/rune/src/compose.rs:34-62, 65-84`). A game could draw its 3D there. But that is a `wgpu` renderer: the Odin Vulkan renderer would have to be ported to wgpu, losing the raw Vulkan control that is the premise. Platform support is whatever wgpu supports; input/focus are moot with one window. **Not viable for an existing Vulkan engine.**

#### 5.4 The sibling route: hand over the paint contract

`docs/research/rune-paint-contract.md` documents the alternative: Rune runs headless, exposes `Runtime::instances`, the atlases and the structural records, and the game reimplements Rune's shader, layer planner, blur and effects in Vulkan. No `wgpu` interop, no FFI for rendering, no shared device. The price is a full renderer port with exact antialiasing, the layer planner, backdrop blur, outline text and the `rune-fx`/`rune-light` families. It is the right route if the goal is to own the UI renderer; it is the wrong route if the goal is to reuse Rune's renderer.

### 6. What Rune's renderer actually needs from the surface

| Path | Target | Source |
|---|---|---|
| Window (desktop) | the acquired swapchain image, viewed with the renderer's format | `crates/rune/src/window/pacing.rs:216-240` (acquire), `window/draw.rs:249-252` (view) |
| Overlay | the overlay's own swapchain image | `crates/rune/src/overlay/frame.rs:87-98` (draw), `overlay/surface.rs` (surface) |
| Embedded (Apple) | the `CAMetalLayer` drawable | `crates/rune/src/platform/embed.rs:172-184` |
| Headless | an `Offscreen` texture Rune owns | `crates/rune/src/render.rs:1020-1060`, used at `tooling/headless.rs:147, 363` |
| Compositor | whatever `TextureView` the host puts in `Frame::target` | `crates/rune/src/compose.rs:65-84` |

So the renderer does **not** require a swapchain, a surface, or a window. It requires:

- a `wgpu::Device` and `wgpu::Queue` (`render.rs:762` takes the device; `Renderer::submit` takes the queue),
- a `TextureView` with `RENDER_ATTACHMENT` and a format the `Renderer` was built for (`render.rs:762`; `draw_range` takes an explicit format for extra targets, `render.rs:789`),
- a `Runtime` stepped by the host's clock (`platform/embed.rs:158-229` shows the host-driven shape),
- and, for the default non-compositor path, nothing else: `draw` clears the view (`render.rs:974-977`), so a dedicated image is the natural target.

The offscreen path can be driven with no window: `Gpu::try_with_features(instance, None, features)` (`tooling/headless.rs:145`) is exactly that, and the whole `headless_run` loop does it every day. A host that wants Rune to draw into *its* texture needs one new module, not a new renderer.

Two format details matter for the handoff:

- Rune prefers a **non-sRGB** target and blends in sRGB space when `srgb_blend` is on (`window.rs:632-648`; the view is created with `format.remove_srgb_suffix()` at `window/draw.rs:249-252`). On Linux `srgb_blend` defaults to false (`runtime.rs:838`), so the natural pairing is a `_SRGB` image with linear blending, i.e. `VK_FORMAT_R8G8B8A8_SRGB` or `B8G8R8A8_SRGB` and `wgpu::TextureFormat::Rgba8UnormSrgb`/`Bgra8UnormSrgb`.
- The `wgpu::TextureDescriptor` and the hal `TextureDescriptor` must carry the same format, extent, mip count and sample count; wgpu does not re-derive them from the `VkImage` (`device.rs:296-320`).

### 7. Recommendation

**Route: share the game's `VkInstance` and `VkDevice` with wgpu, render Rune into a `VkImage` the game owns, and composite that image in the game's own pass.**

This is the only route in this note that meets all four constraints at once — one window, one swapchain, 60 fps, no CPU readback — while still using Rune's renderer. (Route G meets the constraints too, but only by reimplementing Rune's renderer in Odin. Route B meets them in principle but is far more fragile and only works on one GPU.) The per-frame cost is Rune's UI draw plus one alpha-blended textured quad over the UI rectangle.

Concretely:

1. Game startup adopts wgpu's instance/device contract (§1.4). The game keeps ownership through `drop_callback: Some` on the instance and the device (`wgpu-hal-30.0.1/src/vulkan/instance.rs:859-875`, `mod.rs:539-552`).
2. The game creates two or three `VkImage`s at the UI size, in the format Rune will draw with, with `COLOR_ATTACHMENT | SAMPLED` usage, and wraps each once with `texture_from_raw(..., Some(cb), TextureMemory::External)` + `create_texture_from_hal(..., initial_state)`.
3. Each frame: step Rune's `Runtime`, call `Renderer::draw` into the current image's view, finish the encoder with `transition_resources` to the handoff state, submit. Then composite: the game samples the last completed image in its own pass.
4. Synchronize on the same `VkQueue`: the game's submit, then wgpu's submit, then the game's composite, with barriers derived from the declared `initial_state`/final state. Serialize all submits on that queue with one mutex (Vulkan requires external synchronization of a `VkQueue`).
5. Drop wgpu before destroying the `VkDevice`.

**Failure modes**

| Failure | Effect | Mitigation |
|---|---|---|
| The game cannot create its device with wgpu's extensions/features | Adoption impossible; route dies | Decide the feature set up front, before `vkCreateDevice`; if the game needs a feature wgpu's device create info forbids, fall back to §3 or the paint-contract route |
| Feature set reported to `device_from_raw` differs from what `vkCreateDevice` enabled | wgpu uses features the driver did not enable: validation errors, UB | One source of truth for the feature set; assert `hal_device.features() ⊆ vkCreateDevice` features |
| `initial_state` does not match the game's actual layout | Wrong `oldLayout` barrier: validation error or corruption | Use `TextureUses::COLOR_TARGET` / `RESOURCE` and make the game's last transition of the frame match |
| Game and wgpu submit on the same queue from different threads | Vulkan host-synchronization violation | One mutex around both submits |
| Game destroys the image or the device while wgpu has work in flight | Use-after-free | Reference-count the image per frame-in-flight; drop wgpu first |
| wgpu's `required_limits` exceed what the game's device was created with | `create_device_from_hal` error or validation failures | Use `adapter.limits()` from the same adapter for both |
| Rune asks for a feature the game did not enable (dual-source blending for subpixel text, timestamps) | `RequestDeviceError::UnsupportedFeature`; Rune falls back or fails | Enable the union of Rune's optional features at `vkCreateDevice` (`render.rs:471-480`) |
| The game uses a queue family without graphics, or a protected queue | `vkGetDeviceQueue` invalid usage (`flags` must be 0) | Use a plain graphics queue |
| Rune's frame is a separate submission from the game's | One extra submit per frame; small CPU cost | Accept, or batch both encoders via `as_hal_mut` if the risk is worth it |

**Confidence**

- That the API exists at the pinned version: **high**. Every item was read in the local 30.0.1 sources.
- That the route is zero-copy and fits 60 fps: **high** on the mechanism; the only per-frame cost is a UI pass and a composite quad.
- That a given game can adopt it without rewriting its device creation: **medium**. Step 4 is invasive, and a renderer that relies on device features or a queue layout wgpu cannot express will not fit.
- That the effort is bounded: **medium**. The estimate is one Rune host module (~150-250 lines), one shim crate with a C ABI (~300-600 lines including event marshalling), and a device-creation rework in the game. Not a weekend, not a quarter.

**If the safe API is a hard requirement, the answer is no.** There is no safe `wgpu` path to any of this at 30.0.1, and the only supported route is the readback fallback (§3), which copies.

## Route table

| Route | Mechanism | Supported by wgpu 30.0.1 | Per-frame cost | Risk |
|---|---|---|---|---|
| **A. Shared device, wrapped `VkImage`** | `Instance::from_raw` + `device_from_raw` + `texture_from_raw` + `create_texture_from_hal` | Yes, public `unsafe` only; no safe API | Rune draw + one composite draw; no copy | High: device-create contract, queue serialization, manual layout/lifetime |
| **B. Two devices, dma-buf** | Game exports a modifier-tiled image; Rune imports with `texture_from_dmabuf_fd`; external semaphores via hal queue lists | Import yes (feature must be requested); export no; no semaphore API | No copy; import + semaphore overhead | Very high: modifier negotiation, linear render target, two trackers, Rune must opt in |
| **C. Offscreen + CPU readback** | `Offscreen` + `copy_texture_to_buffer` + map + upload | Yes, safe API | 720p/1080p/1440p: 0.5-0.9 / 0.7-1.2 / 1.0-1.6 ms (Gen5) to 1.0-1.6 / 1.8-2.6 / 2.9-3.9 ms (Gen3), plus 1-3 frames latency | Low technical risk; medium performance risk at 1440p on Gen3, and it is a copy |
| **D. Second window / overlay** | Rune's overlay + its own surface and swapchain | Yes | Its own present; compositor-mediated sync | Medium; cannot track the game window on Wayland; focus and placement limits |
| **E. Subprocess + shared texture** | dma-buf + `SCM_RIGHTS` + IPC | Same as B | B plus IPC | Higher than B, no benefit |
| **F. Rune as the only renderer** | Port the engine to wgpu, draw 3D in `Compositor` | Yes | N/A | A renderer rewrite |
| **G. Paint contract** | Rune headless, game reimplements the renderer in Vulkan | N/A (no wgpu interop) | Game's own UI pass; no copy | High effort, exact pixel parity is the hard part (see `rune-paint-contract.md`) |

## Versions and source paths

| Crate / repo | Version | Path |
|---|---|---|
| `rune` | commit `f18ead891aba2437674cd8c54e238287cceb8b3a` (2026-11-10) | `/home/ulezot/Projects/other/rune` |
| `wgpu` | 30.0.1 | `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/wgpu-30.0.1` |
| `wgpu-core` | 30.0.1 | `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/wgpu-core-30.0.1` |
| `wgpu-hal` | 30.0.1 | `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/wgpu-hal-30.0.1` |
| `wgpu-types` | 30.0.1 | `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/wgpu-types-30.0.1` |
| `ash` | 0.38.0+1.3.281 | resolved by `rune/Cargo.lock:205-207` |

`rune` pins `wgpu = "~30.0.1"` at `crates/rune/Cargo.toml:70` (and `30` with `vulkan`+`dx12` on non-Apple native at `Cargo.toml:190-191`); `Cargo.lock:5294-5296` resolves 30.0.1. `wgpu-hal` is not a direct dependency on Linux; the `wgpu::hal` re-export (`wgpu-30.0.1/src/lib.rs:249`) is the intended path.

Local Vulkan: loader 1.4.363, device "AMD Radeon RX 9060 XT (RADV GFX1200)", API 1.4.354, PCIe 5.0 x16 negotiated. The device advertises `VK_EXT_external_memory_dma_buf`, `VK_EXT_image_drm_format_modifier`, `VK_KHR_external_memory_fd` and `VK_KHR_external_semaphore_fd` (`vulkaninfo`).

## Conflicts

1. **DMA_BUF compatibility vs the import VUID.** The handle-type table says dma-buf has "No restriction" on driver/device UUID, while `VUID-VkImportMemoryFdInfoKHR-fd-00668` says the memory "must have been created on the same underlying physical device". The table's own note defers to `vkGetMemoryFdPropertiesKHR`. Treat cross-device dma-buf as same-GPU-or-nothing until the query says otherwise. A design that assumes cross-GPU zero-copy is not supported by the text.
2. **A secondary source says crates.io `wgpu-hal` cannot import dma-buf and needs a vendored patch.** The `tilo_app` docs say "The crates.io wgpu-hal 29 does not enable it; the repository's patched copy … does". That is about 29. In 30.0.1 the feature is advertised (`adapter.rs:1059-1066`) and `texture_from_dmabuf_fd` is public (`device.rs:525`), but the *application* must request `Features::VULKAN_EXTERNAL_MEMORY_DMA_BUF`; Rune does not. Both statements can be true; neither contradicts the code.
3. **"wgpu will destroy the instance" vs keeping ownership.** `wgpu::Instance::from_hal`'s doc says wgpu "will destroy it when the last reference … is dropped" (`api/instance.rs:330-334`), but the hal `from_raw` accepts a `drop_callback` and `InstanceShared::drop` skips `vkDestroyInstance` when one is set (`wgpu-hal-30.0.1/src/vulkan/instance.rs:859-875`). The wgpu doc describes the default; the callback is the exception. Same pattern for the device (`mod.rs:539-552`) and textures (`device.rs:1231-1234`).
4. **"Rune supports embedding" is true only on Apple.** `platform::embed` is `#[cfg(target_vendor = "apple")]` (`crates/rune/src/platform.rs:7-8`) and its header says `CAMetalLayer` (`embed.rs:1-2`). There is no Linux host-view path; the Linux offscreen path is the headless tooling, not `embed`.
5. **This note and `rune-paint-contract.md` describe different architectures.** That note's short answer ("the instance stream is the contract") is correct for the route where the game reimplements the renderer; it does not apply to Route A, where Rune keeps its renderer and hands over a texture. Do not combine the two conclusions.

## Not found

- **No `VkSurfaceKHR` adoption.** `create_surface_from_vk_surface_khr` is `pub(super)` (`wgpu-hal-30.0.1/src/vulkan/instance.rs:548`); every public surface constructor takes a window/display handle. A game cannot hand wgpu the surface its swapchain already uses.
- **No external-memory export** in `wgpu`, `wgpu-core` or `wgpu-hal`: no `VkExportMemoryAllocateInfo`, no `vkGetMemoryFdKHR`, no Win32 handle export.
- **No external-semaphore API**: only the raw hal queue `add_wait_semaphore`/`add_signal_semaphore` escape hatch (`mod.rs:1524-1565`), which the safe layer never exposes.
- **No Rune C ABI.** No `cdylib`/`staticlib` target and no `extern "C"` surface in `crates/rune`; the only `cdylib` crates are web examples and `www/app`.
- **No Rune Vulkan interop module or documentation.** Rune has no `docs/` directory; `crates/rune/README.md` documents the compositor hook (`README.md:2086-2128`) and headless tooling, not host-renderer interop.
- **No measured readback benchmark.** I did not build or run anything, so the §3 numbers are a model plus secondary PCIe measurements, not a measurement of this path on this machine.
- **No validation of a wrapped image's usage.** wgpu stores `desc` and trusts it (`texture_from_raw`, `device.rs:296-320`); there is no check that the `VkImage`'s real usage matches.
- **No Linux embed host in Rune.** `platform::embed` is Apple-only; the closest Linux analogue is `tooling/headless.rs`, which is a capture harness, not a host API.
- **No worked example of `Instance::from_raw` in the published crates.** The crates.io packages of `wgpu`/`wgpu-hal` 30.0.1 ship `src` only (no `tests/` or `examples/`), so the adoption path has no runnable reference in the source we can read.

## References

Primary code, all relative to the stated version:

- `wgpu-30.0.1/src/api/instance.rs` — `from_hal` (335), `as_hal` (372), `create_adapter_from_hal` (392), `enumerate_adapters` (145).
- `wgpu-30.0.1/src/api/adapter.rs` — `create_device_from_hal` (77), `as_hal` (131).
- `wgpu-30.0.1/src/api/device.rs` — `create_texture_from_hal` (341), `create_buffer_from_hal` (463), `as_hal` (668).
- `wgpu-30.0.1/src/api/texture.rs`, `queue.rs`, `command_encoder.rs` — `as_hal` (62, 360), `transition_resources` (431).
- `wgpu-30.0.1/src/lib.rs` — `pub extern crate wgpu_hal as hal` (249).
- `wgpu-30.0.1/build.rs` — `wgpu_core` is always on for native (38-45).
- `wgpu-types-30.0.1/src/instance.rs` — `InstanceDescriptor` (27-62).
- `wgpu-types-30.0.1/src/features.rs` — external-memory features (1225-1248).
- `wgpu-types-30.0.1/src/texture.rs` — `TextureUses` (212-260).
- `wgpu-core-30.0.1/src/instance.rs` — `create_device_from_hal` (1287-1311), `create_device_and_queue_from_hal` (868-886).
- `wgpu-core-30.0.1/src/device/resource.rs` — `create_texture_from_hal` (1244-1262).
- `wgpu-hal-30.0.1/src/vulkan/instance.rs` — `desired_extensions` (227), `from_raw` (317), `create_surface_from_vk_surface_khr` (548), `InstanceShared::drop` (862-875).
- `wgpu-hal-30.0.1/src/vulkan/adapter.rs` — `required_device_extensions` (2516), `physical_device_features` (2547), `device_from_raw` (2570), feature detection (1059-1066), extension enabling (1344-1353).
- `wgpu-hal-30.0.1/src/vulkan/device.rs` — `texture_from_raw` (296), `texture_from_dmabuf_fd` (525), `import_dmabuf_memory` (611), `destroy_texture` (1229), `create_image_without_memory_with_tiling` (358).
- `wgpu-hal-30.0.1/src/vulkan/mod.rs` — `Surface::raw_native_handle` (227), `DeviceShared::drop` (539), `Queue` (650), `TextureMemory` (805), `Texture::{raw_handle, memory}` (831), queue semaphore lists (1519-1565).
- `wgpu-hal-30.0.1/src/vulkan/conv.rs` — `TextureUses` ↔ `VkImageLayout` (247-249), usage flags (268-280), barrier stages/access (300-330).
- `wgpu-hal-30.0.1/src/lib.rs` — `DropCallback` (344), `DropGuard` (347-371), `OpenDevice` (2180), `TextureDescriptor` (2200).
- `rune` `crates/rune/Cargo.toml:70,190-191`; `Cargo.lock:5294-5296` — wgpu pin.
- `rune` `crates/rune/src/render.rs` — `Gpu` (403-411), `Offscreen` (1020-1100), `Renderer::new` (762), `draw` (959), `submit` (947), feature request (471-480).
- `rune` `crates/rune/src/compose.rs` — `Compositor` (34-62), `Frame` (65-84).
- `rune` `crates/rune/src/platform/embed.rs` — `LayerHost` (52-119), `frame` (158-229).
- `rune` `crates/rune/src/tooling/headless.rs` — surface-free GPU (145), offscreen (147), draw (363), copy (372).
- `rune` `crates/rune/src/window/draw.rs:249-252`, `window/pacing.rs:216-240`, `window.rs:632-654` — swapchain path.
- `rune` `crates/rune/src/overlay.rs:1-20`, `overlay/surface.rs` — overlay platform matrix.
- `rune` `crates/rune/src/native_surface/macos.rs:283` and `native_surface/windows.rs:105-140` — Rune already wraps foreign textures through `create_texture_from_hal`.
- `rune` `crates/rune/src/platform.rs:7-8` (Apple-only `embed`), `crates/rune-luau/src/lib.rs:1-25` (UI from Luau scripts).

Vulkan specification and extension pages (Khronos, fetched 2026-11-10):

- `VK_EXT_external_memory_dma_buf`, `VK_KHR_external_semaphore_fd`, `VkExportMemoryAllocateInfo`, `VkImportMemoryFdInfoKHR` (VUID `-fd-00668`, `-fd-01520`), `VkExternalMemoryHandleTypeFlagBits` (compatibility table), `VkImageDrmFormatModifierExplicitCreateInfoEXT`, `vkGetDeviceQueue` (VUID `-flags-01841`).
- Vulkan Guide, "External Memory and Synchronization" — the dedicated-allocation import example.

Secondary (measurements and corroboration, not code evidence):

- PCIe 5.0 x16 measured 52.5 GB/s H2D / 53.3 GB/s D2H (RTX 5090, 2026); 1 MB transfers 18-32 GB/s. `github.com/ForceInjection/AI-fundamentals`, `02_pcie_bandwidth_bench`.
- PCIe 4.0 x16 measured ~24-26 GB/s; 4 MB ≈ 0.25 ms each way (RTX 4090 host data).
- PCIe 3.0 x16 effective ~12 GB/s.
- `tilo_app` `dmabuf_import` docs — a project importing dma-buf into wgpu textures with a patched `wgpu-hal` 29; used only to show the shape and to flag the version difference.
- `rune` `research/34-own-gpu-plan.md:140-146` — Rune's own frame-cost measurements on Metal (≈54 µs CPU for a 2,000-instance frame); Apple hardware, not Linux.
