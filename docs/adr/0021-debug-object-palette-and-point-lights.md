# Debug object palette and point lights

> Shadow visibility is added by [ADR 0040](0040-hard-point-light-shadows.md). The no-shadow statements in this decision describe the state at the time.

Debug mode turns the player into a free-fly camera and edits placed objects through one catalog. The catalog holds crates, construction boxes, a ramp, and three lamp prefabs. Every object is the same unit cube with a transform. A lamp adds an emissive strength and a point light.

## Decisions

- The object palette, placement tool, selection, and inspector share one edit facade. Keyboard and harness actions use the same rules.
- A placed object has a stable id, prefab, body mode, transform, colour, and optional light. Static and dynamic body modes remain available to non-lamp prefabs. Every lamp prefab is dynamic on every creation path, and a static conversion is refused.
- Lamp colour, intensity, and range are editable. Emissive strength follows intensity.
- Every active lamp enters the frame light list. Cluster assignment limits the per-fragment loop to lights whose ranges overlap the view cluster.
- Placement, deletion, duplication, movement, rotation, and body conversion use the undo history. Light edits use the same selection and inspector.
- The ghost, footprint, height guide, selection outline, and palette preview use the existing box geometry and debug lines.
- A spawn pop changes only the visual box. The physics body keeps its full shape.

## Considered Options

- **Separate light editing mode**: rejected. A lamp is a placed object and uses the same selection, transform, and history path.
- **A nearest-light subset**: rejected. It makes lighting depend on camera distance and drops visible lamps. The growable list and clusters avoid that cap.

## Consequences

- `scenarios/initial-lamps.json` covers the three starting lamps and a moved light. `scenarios/editor-lamps.json` covers all lamp previews, placement, light values, selection, editing, and undo.
- `scenarios/light-move.json` proves that the current transform drives the light field.
- Direct lights have no shadow visibility term. The editor does not expose lighting systems that the renderer does not have.
