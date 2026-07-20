---
name: pilz-designer
description: Design language and how-to for PilzBuddy's cute mushroom artwork — use whenever creating or changing mushroom icons, map markers, animations, app icons, or any mushroom illustration in this project.
---

# PilzBuddy Mushroom Design Language

Every mushroom in PilzBuddy is a **buddy**: small, chubby, colorful, and friendly.
The app is about sharing mushroom spots with friends — the artwork must radiate that.

## Character rules (never break these)

1. **Always a friendly face.** Two round dark eyes (`#3E2723`) and an upward
   smile (stroked quadratic curve, round caps). Roughly half of the variants
   get rosy cheeks (`#F8BBD0` at ~90% opacity). No angry, sad, or neutral faces.
2. **Chubby proportions.** Cap clearly wider than the stem; stem short and
   plump with rounded corners. Think plush toy, not botanical drawing.
3. **Readable at 44 px.** Icons are used as map markers at 44 logical pixels.
   Every new design must stay recognizable at that size — test it.
4. **White halo + soft outline.** All silhouettes get a white halo stroke
   (~0.09 of the width) so they pop on any map background, plus a soft
   dark-brown outline (`#4E342E` at 75% opacity, ~0.025 width).
5. **Ground ellipse shows ownership.** Every mushroom stands on a soft
   ground ellipse: green (`#2E7D32`) for the user's own spots, blue
   (`#1565C0`) for community/friend spots — drawn behind the mushroom
   at ~55% opacity.

## Where the code lives

- `lib/core/widgets/mushroom_icon.dart` — `MushroomIcon` widget +
  `_MushroomPainter` (CustomPaint). All drawing happens in relative
  coordinates via `u(v) = v * width` on a square canvas; the mushroom stands
  on the bottom edge (map markers use `alignment: Alignment.topCenter`).
- `lib/core/mushroom_species.dart` — species list and `SpeciesGroup` enum;
  `groupFor(name)` maps a species name to its group.
- `lib/core/widgets/buddy_mushrooms.dart` — the animated pair from the app
  icon (login screen). Gentle sway only: rotate around `bottomCenter`,
  ±0.05 rad max, phase-shifted between buddies, 4 s loop.
- `lib/features/intro/intro_overlay.dart` — grow-from-the-ground intro
  (elastic scale from `bottomCenter`, staggered, ~2.6 s, tap to skip).
- `assets/icon/icon.svg` — full-bleed app icon source (the two buddies in a
  close crop, scaled 1.9 around the cluster centre; the location pin no
  longer fits and was dropped). `assets/icon/icon_fg.svg` is the Android
  adaptive foreground: same buddies on transparent ground, scaled 1.12 and
  centred so the outermost painted point stays inside the launcher mask
  (circle r=341 around 512,512 — only the middle 66 % is guaranteed visible).
  Regenerate with `rsvg-convert -w 1024 -h 1024 <in>.svg -o <out>.png`, then
  `dart run flutter_launcher_icons`. **Do not use `qlmanage` for this** — it
  flattens alpha onto white, which turns the adaptive foreground into an
  opaque white tile instead of letting the green background show through.

## Group looks (keep icons true to the species group)

| Group (`SpeciesGroup`) | Shape | Palette |
|---|---|---|
| roehrlinge | round dome, thick stem | browns `#795548 #8D6E63 #5D4037` |
| leistlinge | wavy funnel (concave top) | yellows `#F9A825 #FBC02D #F57F17` |
| champignons | dome | cream whites `#F0EAD8 #EDE3CE` |
| schirmlinge | wide flat cap, tall stem, dark scales | tans `#C8A165 #B78F5C` |
| wulstlinge | dome **with white dots** | reds `#E53935 #D32F2F #C62828` |
| taeublinge | flat cap | vivid mix red/violet/green/amber/pink |
| morcheln | cone with dark honeycomb dots | dark browns `#6D4C41 #5D4037` |
| boviste | ball (face on the ball, mini foot) | off-white `#F3F1E7` |
| baumpilze | shelf/bracket on a short base, face on cap | oranges `#EF6C00 #D18B47` |
| sonstige | dome/cone | muted `#BCAAA4 #A1887F #90A4AE` |
| unknown/own species (`group == null`) | seed-random dome/cone/flat | 7-color fun palette |

Variation within a group comes from the spot's stable seed
(`stableSeed(spotId)`): color pick, dots on/off (where optional), cheeks.
Same spot → same look, forever.

## Species-specific looks (override the group)

`MushroomIcon(species: …)` — matched by name substring in
`_speciesStyleFor` (`mushroom_icon.dart`); falls back to the group style:

| Species contains | Shape | Look |
|---|---|---|
| pfifferling | chanterelle | deep wavy egg-yellow funnel, **yellow stem** (cap flows into stem) |
| trompete | trumpet | slim dark gray-brown horn with flared wavy rim, dark stem (face stays readable, morel precedent) |
| reizker | flat + rings | concentric darker ring zones, light-orange stem; cap tone per variant: edel `#E8833A`, lachs `#EF8A66`, kiefern `#C96A2E`, fichten `#D9702E` |
| marone / braunkappe | dome | chestnut cap `#6B4423/#5D3A21`, pale-yellow stem (vs. Steinpilz: lighter browns, cream stem) |

Wire-up: map markers and the spot detail sheet pass
`species: spot.lastFind?.species`. When adding a species look, extend the
preview rows in `test/icon_preview_test.dart` and re-render the sheet.

## Avatars (portraits)

- `lib/core/widgets/mushroom_avatar.dart` — `MushroomAvatar` renders a buddy
  as a round portrait: warm cream circle (`#FDF6E3`), soft brown ring, **no
  ground ellipse** (that is map-ownership language; pass `ground: false`).
- The selectable catalog is `kAvatarCatalog` (seed + group pairs covering all
  ten cap shapes plus seed-random free spirits). **Never reorder or remove
  entries** — the index is persisted in `profiles.avatar`; append only.
- Shown in: profile header (picker via tap), friends lists, spot detail
  finder row. Sizes range 22–64 px — check readability at 22 px.

## Animation rules

- Subtle and organic: sway, breathe, or grow — never spin, bounce hard, or flash.
- Anchor transforms at `Alignment.bottomCenter` (mushrooms are rooted).
- Loops ≥ 3 s; entrance animations ≤ 3 s and skippable.
- Keep it cheap: one `AnimationController`, `AnimatedBuilder`, no rebuild storms.

## Checklist for any new mushroom artwork

- [ ] Friendly face, correct proportions, halo + outline
- [ ] Recognizable at 44 px (markers) and 30 px (detail sheet)
- [ ] Group-faithful shape/palette (table above) or seed-driven for unknown
- [ ] Deterministic from seed — no `Random()` without a seed
- [ ] `flutter analyze` clean; verify visually in Chrome
      (`flutter run -d chrome --web-port 3000`), ideally with a screenshot
