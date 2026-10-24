# Offscreen submission serialization

The offscreen target keeps one frame in flight. The swapchain target keeps two.
`renderer.frames_in_flight` is the single place that decides the count.

## Why

The offscreen target owns one color image and one readback buffer. The swapchain rotates through its own images, so two submissions write different images. With two frames in flight on the offscreen path, the second submission can write the color image while the first frame still reads it. Nothing waits for the first submission unless the frame captures; a capture-free settle sequence is exactly that case. The readback also serves one frame at a time, so two captures in flight would race on it.

## Considered Options

- **Several offscreen images with per-image fences and semaphores**: keeps two frames in flight, but the offscreen path gains a rotation it does not need. A harness frame is not on a display clock, so the extra overlap buys no throughput.
- **Wait for the fence after every capture-free offscreen submit**: serializes the queue, but leaves the frame ring and the readback ring misaligned. The rule would live in `end_frame`, far from the target that owns the image.
- **One frame in flight through the existing frame index**: the frame index drives the command buffer, the fences, the camera and object buffers, the TAA slot, and the timing pool. Bounding it bounds every one of those together.

## Consequences

- An offscreen frame waits for the previous offscreen frame before it records. The wait costs nothing when the GPU is ahead, which is the usual harness case.
- A capture-free sequence cannot overlap two writes to the color image or the readback buffer, so it is deterministic.
- The swapchain path keeps its two frames in flight and its pacing.
- The rule is a property of the target kind, so a new target must state its own count.
