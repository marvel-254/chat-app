# Auth prop sources

The auth screens each use **exactly one** 3D prop. All four are original BRO
artwork generated for this project — there are no third-party renders and no
attribution requirements to carry forward.

| Asset | Screen | Role | Intrinsic size | Size on disk |
| --- | --- | --- | --- | --- |
| `prop_mascot.webp` | Login / sign up | Full-body mascot ("Bro"), waving | 560 × 1003 | ~70 KB |
| `prop_chat.webp` | Onboarding 1 — people | Two rounded chat bubbles | 520 × 417 | ~29 KB |
| `prop_circle.webp` | Onboarding 2 — your circle | Charcoal/volt torus | 510 × 462 | ~40 KB |
| `prop_bolt.webp` | Onboarding 3 — fast & personal | Chunky lightning bolt | 300 × 507 | ~28 KB |

Total: ~167 KB of WebP.

## Art direction

- **Palette:** near-black charcoal surfaces (`#121318`–`#292A2F`) with volt lime
  (`#D4FF00`) emissive accents — the same "Electric Street" palette as the UI.
- **Material:** soft-touch matte composite with a polished lime bevel.
- **Lighting:** one studio key from the upper left with a lime rim light. No
  baked floor, no glow spill into the background — the app adds its own halo
  and contact shadow so the prop sits on the backdrop instead of on a card.
- **Composition:** one object, centred, nothing orbiting it and nothing staged
  around it. Props read as objects in a room, not as a set of easter eggs.
- **Typography:** none baked into the art. Every headline is live Space Grotesk
  text, so copy changes never require a re-render.

## Regenerating

Props are produced from a flat magenta (`#FF00FF`) chroma background and keyed
to alpha. Generate a single isolated object per image on a uniform magenta
field, then:

1. Key on "magenta-ness" (`min(R, B) − G`) with a soft ramp (~20 → 95) rather
   than plain RGB distance — it survives uneven chroma spill from the render's
   own glow.
2. Un-mix the magenta out of partial-coverage edge pixels and despill any
   residual cast, so hair, glass and bevels keep neutral edges.
3. Crop to the silhouette (no padding), resize to roughly 2× the on-screen size
   and export WebP (`quality 92`, method 6).

Keep the file paths in `pubspec.yaml`; `AuthArt` in
`lib/screens/auth/widgets/auth_prop.dart` is the only Dart reference to them.
