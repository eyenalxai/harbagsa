# 0027 Multi-output captures

## Decision

A `captures` command renders one frame and writes up to eight outputs from that
frame. Each output carries one target and one format, so a color PNG, the
history statistics, and a linear profile can describe the same pixels.

The renderer copies every requested target into one readback buffer at a fixed
slot stride. The harness maps each request to its target's slot and decodes the
slot with the existing single-target conversion. A plain `capture` stays the
one-output form.

## Why

Separate captures advance the frame between readbacks. In a moving or temporal
scene the PNG and the statistics then describe different frames, which makes an
A/B or a convergence claim wrong. A sidecar fixed only the PNG-plus-summary
case; a history or depth read still needed another render.

The slot stride uses the largest texel size, so one buffer layout serves every
target. Growing the buffer waits for the device because the readback is shared
across frames in flight.

## Consequence

`capture.count` counts outputs, not frames. The PNG delta series still sees one frame per color PNG output. A recorded session does
not record a capture group; use explicit `capture` commands when the recording
must contain the readouts.
