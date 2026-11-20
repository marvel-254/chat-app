# Hero artwork sources

All four welcome-screen hero props are **original BRO artwork**, generated in-house
on 2026-11-20 for the auth look pass. They replace the earlier third-party
transparent renders, whose commercial-use terms had never been verified.

| Asset | Role in the scene | Intrinsic size | Size on disk |
| --- | --- | --- | --- |
| `hero_mascot.webp` | Full-body mascot ("Bro"), waving | 560 × 1003 | ~70 KB |
| `hero_ball.webp` | Charcoal/volt football orb | 300 × 210 | ~20 KB |
| `hero_gamepad.webp` | Charcoal/volt game controller | 480 × 283 | ~21 KB |
| `hero_supercar.webp` | Original graphite/volt supercar (no real model, no badges) | 512 × 229 | ~26 KB |

## Art direction

- **Palette:** near-black charcoal surfaces (`#121318`–`#292A2F`) with volt lime
  (`#D4FF00`) emissive accents — the same "Electric Street" palette the UI uses.
- **Material:** soft-touch matte fabric/composite with chrome specular edge light.
- **Lighting:** studio key light with a lime rim light, no baked floor or shadow —
  the app draws its own contact shadow so the props composite cleanly over the
  auth backdrop in both light and dark surfaces.
- **Typography:** none baked into the art. All lettering in the hero is live text
  set in Space Grotesk (`AppText`), so copy changes never require a re-render.

## Regenerating

The props are produced from flat magenta (`#FF00FF`) chroma backgrounds and keyed
to alpha. If you need to redo them, generate a single isolated prop per image on
a uniform magenta field, then:

1. Key the background to alpha with a soft ramp (background distance ≈ 40–115)
   and un-mix the magenta from partial-coverage edge pixels.
2. Despill any residual magenta so hair, glass and wheels keep neutral edges.
3. Drop the baked shadow / keep the largest connected silhouette.
4. Resize to the sizes above and export WebP (`quality 92`, method 6).

Keep the output files at the paths in `pubspec.yaml`; `HeroArt` in
`lib/screens/auth/widgets/welcome_hero.dart` is the single place that references
them from Dart.

These files are original generated artwork for this project; there are no
third-party attribution requirements to carry forward.
