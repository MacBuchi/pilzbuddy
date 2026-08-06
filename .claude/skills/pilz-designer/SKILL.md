---
name: pilz-designer
description: Design language and how-to for PilzBuddy's cute mushroom artwork — use whenever creating or changing mushroom icons, map markers, animations, app icons, or any mushroom illustration in this project. Also covers adding a species to the list, because the group you file it under decides what it looks like and what the app tells the user about it.
---

# PilzBuddy Mushroom Design Language

Every mushroom in PilzBuddy is a **buddy**: small, chubby, colorful, and friendly.
The app is about sharing mushroom spots with friends — the artwork must radiate that.

## Look the mushroom up before you draw it or file it

**Never design from the name, and never pick a group from a keyword.** Read up
on the actual species first. Four things decide four different parts of the
work:

| What to look up | What it decides |
|---|---|
| Cap shape and profile (domed? flat? bell? none at all?) | the `_CapShape` — or whether a new one is needed |
| Cap colour, in the mushroom's own terms | the palette |
| **The underside — gills, tubes, spines, or none** | **the `SpeciesGroup`** |
| Stem — stout, slender, tall, or absent | `stemTop`, `stemColor`, or an empty stem path |

Then find the **one field mark** a picker uses to tell it from its look-alike.
That mark is what the icon has to carry at 44 px; everything else is decoration.
Netted vs flecked stem on the two Hexenröhrlinge, spines vs gills on the
Semmelstoppelpilz, a striate margin on the Scheidenstreifling.

**The group is not just an icon switch — its label is shown to the user**, as a
badge next to the entry in the species field (`_groupBadge` in
`species_field.dart`). Filing a tooth fungus under `sonstige` does not merely
give it a grey cone; it prints "Lamellenpilz" next to a mushroom that has no
gills.

This is where things have actually gone wrong. `tool/feedback_bot.py` files
requested species by keyword, and a keyword cannot know what is under the cap:

- "Böhmische Verpel" matched nothing → `sonstige` → a grey gilled mushroom,
  though it is a morel relative.
- "Morchelbecherling" matched `morchel` → right group, but the group icon is a
  cone and the mushroom is a bowl.
- "Netzstieliger Hexenröhrling" matched `röhrling` → right group, but drawn as
  a plain brown bolete, i.e. as a Steinpilz. That is the one confusion that
  matters in the field.

Bot output is a starting point, not a decision. Check every species it files.

## Verify every name against German Wikipedia

Not just the shape — the **names** too. Before adding a species or a `sameAs`
second name, open the German Wikipedia article and read the lead: the trivial
names are listed there, and it also tells you when a name is shared by two
species.

**If the article does not corroborate the name, drop it.** A wrong synonym
merges two species permanently — in the filter, in the tally, in the
statistics, and for every spot already logged. A missing one merely misses.

Real outcomes of doing this (1.37.0):

- `Grünreizker` → Grünling: **dropped.** No Wikipedia entry at all, and the
  Grünling article does not know the name. „Reizker" otherwise always means a
  *Lactarius*, so the name may well point somewhere else entirely.
- `Stockschwamm` → Stockschwämmchen: **dropped.** Not corroborated for
  *Kuehneromyces*. It had already been added on a hunch — the check caught it.
- `Braunkappe`: the article lists it for **both** Maronenröhrling and
  Riesenträuschling. Genuinely ambiguous, so it is not a fact to look up but a
  decision to put to the operator — which reading do they use?
- `Winterrübling`: a redirect to Gemeiner Samtfußrübling. The species list had
  carried both as separate entries all along.

Names Wikipedia writes with a hyphen (`Butter-Röhrling`, `Mai-Ritterling`,
`Fichten-Steinpilz`) go into the list unhyphenated — the file's own style, and
`Maronenröhrling` sets the precedent.

## Character rules (never break these)

1. **Always a friendly face.** Two round dark eyes (`#3E2723`) and an upward
   smile (stroked quadratic curve, round caps). Roughly half of the variants
   get rosy cheeks (`#F8BBD0` at ~90% opacity). No angry, sad, or neutral faces.
   **On the nine straight cap shapes the face sits on the STEM**, so a dark
   stem swallows it — the Samtfußrübling's first render had nothing left but
   the cheeks at 44 px. Such a style needs `lightFace: true` (cream instead
   of `faceBrown`). Set it explicitly per species; a brightness threshold
   would also repaint the Herbsttrompete, which nobody asked for.
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
   at ~55% opacity. **It has to stay visible.** A stemless shape that sits
   flat on the ground covers it and loses the green/blue signal — end its
   lower edge around 0.87 instead (see `ruffle`).

## Where the code lives

- `lib/core/widgets/mushroom_icon.dart` — `MushroomIcon` widget +
  `_MushroomPainter` (CustomPaint). All drawing happens in relative
  coordinates via `u(v) = v * width` on a square canvas; the mushroom stands
  on the bottom edge (map markers use `alignment: Alignment.topCenter`).
- `lib/core/mushroom_species.dart` — species list and `SpeciesGroup` enum;
  `groupFor(name)` maps a species name to its group. The enum is **never
  persisted** — it is derived from the name — so adding a value is safe.
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

| Group (`SpeciesGroup`) | Label shown to the user | Shape | Palette |
|---|---|---|---|
| roehrlinge | Röhrling | round dome, thick stem | browns `#795548 #8D6E63 #5D4037` |
| leistlinge | Pfifferlingsartig | wavy funnel (concave top) | yellows `#F9A825 #FBC02D #F57F17` |
| champignons | Champignon | dome | cream whites `#F0EAD8 #EDE3CE` |
| schirmlinge | Schirmling | wide flat cap, tall stem, dark scales | tans `#C8A165 #B78F5C` |
| wulstlinge | Wulstling | dome **with white dots** | reds `#E53935 #D32F2F #C62828` |
| taeublinge | Täubling/Milchling | flat cap | vivid mix red/violet/green/amber/pink |
| morcheln | Morchel/Lorchel | cone with dark honeycomb dots | dark browns `#8D6E63 #7D5F52` |
| boviste | Bovist | ball (face on the ball, mini foot) | off-white `#F3F1E7` |
| baumpilze | Baumpilz | shelf/bracket on a short base, face on cap | oranges `#EF6C00 #D18B47` |
| stachelpilze | Stachel-/Korallenpilz | toothed cap | muted ochres `#D9C39A #C9B184 #E0CFAA` |
| sonstige | Lamellenpilz | dome/cone | muted `#BCAAA4 #A1887F #90A4AE` |
| unknown/own species (`group == null`) | — | seed-random dome/cone/flat | 7-color fun palette |

`stachelpilze` exists because `sonstige` says "Lamellenpilz" out loud. Anything
without gills belongs here: tooth fungi, corals, the Krause Glucke. **Growing on
wood does not make it a `baumpilze`** — that group is for brackets. The
Igelstachelbart sits on deadwood and is still a tooth fungus.

Variation within a group comes from the spot's stable seed
(`stableSeed(spotId)`): color pick, dots on/off (where optional), cheeks.
Same spot → same look, forever.

## Species-specific looks (override the group)

`MushroomIcon(species: …)` — matched by name substring in
`_speciesStyleFor` (`mushroom_icon.dart`); falls back to the group style:

| Species contains | Shape | Look |
|---|---|---|
| pfifferling | chanterelle | deep wavy egg-yellow funnel, **yellow stem** (cap flows into stem) |
| trompete | trumpet | slim dark gray-brown horn with flared wavy rim, dark stem |
| reizker | flat + `rings` | concentric darker zones, light-orange stem; cap tone per variant: edel `#E8833A`, lachs `#EF8A66`, kiefern `#C96A2E`, fichten `#D9702E` |
| marone | dome | chestnut cap `#6B4423/#5D3A21`, pale-yellow stem (vs. Steinpilz: lighter browns, cream stem). „Braunkappe" was matched here until 1.37.0 and is now the Riesenträuschling — see the Wikipedia rule above |
| steinpilz | dome + `stemBulge` | the group's browns and cream stem unchanged — the difference to the Marone stays the lighter cap. What is its own is the **club-shaped stem**, its loudest field mark. Also catches Fichten-/Sommersteinpilz |
| samtfußrübling | dome + thin `stemWidth` | honey-orange cap `#F0A030/#E8912A/#F5B950` on a slim dark stem `#5D4037` — the velvet foot is the name *and* the mark against the deadly Gifthäubling. Needs `lightFace`, see below. Stays in `sonstige`: it has gills |
| hexenröhrling | dome + `poreBand` | olive-brown cap `#8D7040/#9A7B4F`, red pore band, yellow stem; `stemPattern` splits the pair — `net` if the name contains "netz", else `flecks` |
| stoppelpilz | toothed | low irregular bread-crust cap `#E3B981/#D9A96C/#E8C593`, pale stem |
| habichtspilz | toothed + `darkDots` | same cap, dark brown `#8A6A45/#77593A` with coarse scales |
| glucke | ruffle + `folds` | pale lobed mass `#EBD9A8/#E0C88F/#F0E3BC`, **no stem** |
| stachelbart | beard | whitish knob `#F7F1E3/#F0E8D6/#FBF6EA` with a mane of hanging spines, **no stem**; the spines hang off a closed body — notches cut into the body read as a jester's collar |
| ziegenbart | coral | ochre trunk with five splayed clubs `#E0B355/#D3A247/#E8C778`, **no stem** |
| becherling | cup + `veins` | ochre bowl `#C9A87C/#BE9B6E`, dark interior with radiating veins, stub foot |
| verpel | thimble + `ridges` | olive-brown bell `#8A6D3B/#7A5F33`, longitudinal wrinkles, long pale stem |
| käppchenmorchel | semifreeCone + `darkDots` | small honeycombed cap `#7D6552/#6E5949` on a long pale stem |
| scheidenstreifling | dome + `ridges` | grey-brown `#9C9184/#8B8175`, striate margin, **no dots** — the group's red-with-white-dots would be the most misleading thing an icon could say about it |

**Second names need no entry of their own.** `_speciesStyleFor` resolves the
name through `canonicalSpecies` before matching, so a species look is inherited
by every `sameAs` pointing at it — „Löwenmähne" arrives as „Igelstachelbart",
„Marone" as „Maronenröhrling". Add the look for the main name only.

**Match order matters.** The checks run top to bottom and the first hit wins, so
a broad name must never sit above a longer one that contains it. `becherling`
is placed above the morel branches for that reason: "Morchelbecherling" would
be swallowed whole by a plain `morchel` matcher. Today's matcher is the narrow
`käppchenmorchel`, so that collision is latent rather than live — the comment
in `_speciesStyleFor` states it as if it were live and should be corrected the
next time the file is edited for a real reason.

Wire-up: map markers and the spot detail sheet pass
`species: spot.lastFind?.species`. When adding a species look, extend the
preview rows in `test/icon_preview_test.dart` (and raise the surface height —
the column overflows and the test fails, which is the reminder).

**List rows** use `MushroomIcon.forSpecies(name)` (24–28 px): no ground
ellipse, and the seed comes from the species name so the same species looks
identical in every list. Never put a bare `🍄` in a species row — most systems
render it as a red fly agaric, which makes every mushroom look poisonous.

## Building a new shape

`_CapShape` today: `dome cone flat funnel ball shelf chanterelle trumpet
semifreeCone thimble cup toothed ruffle coral beard`.

Three idioms worth reusing:

- **No stem is an empty path.** `stemPath = Path()` — halo, fill and outline
  then draw nothing, and no branch is needed anywhere else. `ruffle` and
  `coral` do this. Use it when the mushroom genuinely has no stem; do not fake
  one to keep the code uniform.
- **Details that belong to the silhouette go into the cap path.** The
  Semmelstoppelpilz's spines are a zigzag on the cap's lower edge, not a
  separate detail pass — so halo, fill and outline pick them up for free.
- **A bundle of branches needs subpaths, not a clever outline.** The Ziegenbart
  is a trunk plus five clubs added to the same `Path`. The outlines *between*
  the parts are what makes it read as a coral. A single closed silhouette reads
  as a **hand** no matter how deep the notches — two attempts confirmed that
  before switching. If a shape needs to look like separate pieces, draw
  separate subpaths.

**Detail flags are shape-aware where they have to be.** `darkDots` and `ridges`
each carry two idioms, branched on `style.shape`: the full-size morel dot
layout vs the denser one for the small `semifreeCone` cap; the thimble's
full-height wrinkles vs the dome's short radial grooves at the rim. Adding a
third idiom to an existing flag is fine; silently retuning a shared one is not
— it would change every icon already using it.

## Paint order (do not reshuffle)

`_MushroomPainter.paint` draws: ground → halo (stem, cap) → stem fill →
**stem pattern** → **stem outline** → cap fill → cap details (clipped to the
cap) → cap outline → face. The stem outline has to come *before* the cap fill:
the stem runs under the cap in every shape, and an outline stroked afterwards
sits visibly on top of the cap (#115).

## Avatars (portraits)

- `lib/core/widgets/mushroom_avatar.dart` — `MushroomAvatar` renders a buddy
  as a round portrait: warm cream circle (`#FDF6E3`), soft brown ring, **no
  ground ellipse** (that is map-ownership language; pass `ground: false`).
- The selectable catalog is `kAvatarCatalog` (seed + group pairs covering the
  cap shapes plus seed-random free spirits). **Never reorder or remove
  entries, and never insert one in the middle** — the index is persisted in
  `profiles.avatar`, so an insert silently repaints every user behind it.
  Append only. `test/species_test.dart` ("Avatar-Katalog") pins the boundary
  where such an insert would first show up.
- Shown in: profile header (picker via tap), friends lists, spot detail
  finder row. Sizes range 22–64 px — check readability at 22 px.

## Animation rules

- Subtle and organic: sway, breathe, or grow — never spin, bounce hard, or flash.
- Anchor transforms at `Alignment.bottomCenter` (mushrooms are rooted).
- Loops ≥ 3 s; entrance animations ≤ 3 s and skippable.
- Keep it cheap: one `AnimationController`, `AnimatedBuilder`, no rebuild storms.

## The design review loop

Render the overview sheet and **look at it** — this is the review, not a
formality:

```
flutter test test/icon_preview_test.dart --dart-define=PILZ_PREVIEW_DIR=<dir>
```

That writes `mushroom_preview.png` (every group in five seed variants, plus one
row per species-specific look at 44/72/30/28/24 px, including the friend
variant). Crop into it to judge a single row —
`sips -c <h> <w> --cropOffset <top> <left> file.png`, then `sips -Z 1400`.
Labels render as red bars: no font is loaded in the test environment, which is
expected.

Expect to iterate. Every icon in this project needed at least one pass after
looking at it — flecks too faint at 24 px, a skirt too flat, a cap too domed,
a stemless shape covering its own ownership ellipse, a coral that was a hand.

## Checklist for any new mushroom artwork

- [ ] Looked the species up first — cap, colour, underside, stem
- [ ] Group chosen from the underside, and its **label** is true for this mushroom
- [ ] The field mark that distinguishes it from its look-alike is visible at 44 px
- [ ] Friendly face, correct proportions, halo + outline
- [ ] Ground ellipse still visible (matters for stemless shapes)
- [ ] Recognizable at 44 px (markers), 30 px (detail sheet), 24 px (list rows)
- [ ] Row added to `test/icon_preview_test.dart`, preview rendered **and viewed**
- [ ] Deterministic from seed — no `Random()` without a seed
- [ ] `flutter analyze` clean, `flutter test` green

## Known debt

- The `becherling`/`morchel` comment in `_speciesStyleFor` (see above).

Not worth a version bump on its own: any edit under `lib/` trips the version
guard, and a bump publishes a release and an update prompt to every user. Ride
along with the next real change — that is how the Igelstachelbart got fixed,
in the PR that was already touching the species list.
