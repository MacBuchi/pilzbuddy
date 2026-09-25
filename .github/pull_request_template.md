## What

<!-- What changes and why. English, as everywhere on GitHub. -->

## Tests

<!-- What was run; which test was made red on purpose (counter-probe). -->

## Checklist

- [ ] **Visible feature?** Entry in `kFeatureHighlights` (highlight if it belongs in the sheet after an update, otherwise tip) **plus its demo** in `highlight_demos.dart` — or one sentence here why not. The sheet picks its content by `since`; a missing entry means the feature ships unannounced.
- [ ] **UI a tour or demo points at changed?** Anchors (`CoachAnchor`) still in place; `map_tour_flow_test`, `tab_tours_flow_test` and `highlight_demos_flow_test` green.
- [ ] Version bump + `CHANGELOG.md` block if anything under `lib/` or `assets/` changed.
- [ ] New network target, permission or data category? → `web/datenschutz.html`, `docs/play-console.md`, `docs/datenschutz-nachweise.md` in this PR.
- [ ] Schema change? → `patch_NNN`, `schema.sql` structure **and** seed list.
