# Nanashi Cold Glass preview

This iteration is a native simulator preview for review in Device Hub. It does not install or
modify the iPhone copy. The previously rejected Noir minéral/build 442 work was rolled back;
it is not the current design.

## Source mapping

| Family | Retrieved source | Native adaptation |
| --- | --- | --- |
| Cards and backdrop | [Glass Card, educalvolpz](https://21st.dev/@educalvolpz/components/glass-card) | Frosted face, directional highlights, polished inset edge and drop shadow. SwiftUI material replaces SVG displacement; the demo gradient uses Harbor Blue colors. |
| Buttons and control material | [Glass Button, jahed](https://21st.dev/@jahed/components/glass-button) | Pill silhouette, diagonal reflection and finite press feedback; native fields retain keyboard, focus, validation and accessibility semantics. |
| Dock and Activity switcher | [Pill Morph Tabs, ruixen.ui](https://21st.dev/@ruixen.ui/components/pill-morph-tabs) | Glass rail with a moving selected plate, stable touch targets and permanent destination labels. |
| Coach composer | [Assistant Composer, konsstepnov](https://21st.dev/@konsstepnov/components/assistant-composer) | Growing input, bottom action row and send/stop state connected to the existing native Coach. |
| Chrome and text colors | [Harbor Blue, serafimcloud](https://21st.dev/community/themes/harbor-blue) | Native light/dark tokens. Pale chart-5 becomes the dark-mode accent for contrast. Physiological colors retain their existing meaning. |
| Native mark and iOS icons | Orbit Rotation, component 18010 in the source ledger | The existing product N is larger and thicker, inside one open arc. Dotted and satellite details are removed. Native and exported icons read the same vector proportions. |

The dashboard retains the sourced Stats Bento, Radial Chart, Activity Card and Stats Card
compositions with a more compact hierarchy. Recorded-night comparison composes the existing
Stats Card and Preferences Card patterns. Their exact IDs, cached code, destination files and
historical evidence are recorded in [the source ledger](../.21st/sources.json).

These are native SwiftUI adaptations, not unchanged React components. No browser wrapper,
CSS runtime, WebGL dependency, pointer-tracked shine or physical spatial refraction is embedded.
Native system controls, permission dialogs, keyboard, SF Symbols and existing physiological
charts retain their own product/platform provenance. No blanket claim is made that every OS
control is a catalog component. Source bundles without an explicit license notice are marked
as such rather than assigned an invented license.

## Product and implementation boundaries

The implemented changes are:

- A compact daily score hierarchy, visible navigation labels and consistent glass controls.
- **Comparison of two recorded nights:** explicit dates, factual duration differences, recorded
  stages and exact-day readings. Missing data remains absent rather than becoming zero.
- **Stable sleep navigation:** the selected night survives refresh and remains accessible when
  Stages is hidden. Historical detail resolves the selected night instead of falling back to the
  latest night. A corrected night can refresh Trends without adding another day.
- **Activity sections:** Workouts and Trends keep independent period, filter and scroll state
  after being visited. The legacy Trends route opens the Trends section explicitly.
- **Coach:** a growing composer, reachable Stop and Retry controls, and optional return to the
  latest response when reading older history. Async restoration cannot overwrite a new conversation;
  stale model-list results cannot replace a newer provider/connection selection.
- A larger N and single open arc shared by the native mark and regenerated iOS primary/Navy icons.

These changes add no physiological formula, schema migration, backend service or telemetry.

Glass consists of static optical layers and native material. Reduced Transparency uses opaque
surfaces; Reduced Motion disables positional feedback. Synthetic demo fixtures are used for
visual review, without exporting the user's health history.

## Verification

The final iOS simulator and macOS application builds passed. Exact exercised paths, logs and
limitations are recorded in [the decision record](../.21st/design.json). The interactive preview
is left open as **Nanashi Cold Glass** in Device Hub for user review.

| Check | Result and evidence |
| --- | --- |
| iOS app compilation | Final `NOOPiOS` simulator build succeeded: [log](../build/nanashi-coldglass/ios-build-delivery.log). No iPhone installation is implied. |
| macOS app compilation | Final `Strand` build succeeded: [log](../build/nanashi-coldglass/mac-build-delivery.log). |
| Selected application tests | 86 distinct methods passed across the iteration. The [final focused run](../build/nanashi-coldglass/mac-tests-reviewed.log) passed 43/43. The [initial run](../build/nanashi-coldglass/mac-tests.log) plus [locale rerun](../build/nanashi-coldglass/mac-charge-en-args.log) cover the other methods. Four existing English-string tests required process-only English locale; Coach lifecycle fixtures were made locale-aware without weakening exact body/identity assertions. |
| StrandDesign package tests | All 134 methods passed using the existing package test bundle with process-only English arguments: [log](../build/nanashi-coldglass/design-en-hosted.log). Global language preferences were not changed. This bundle predates the final identity/layout refinements. |
| Dark iPhone 13 simulator | Daily hierarchy, Sleep comparison dates/duration delta, selected-night retention after tab retap/refresh, Activity's 30-day period across section switches, and Explorer search reaching Devices were exercised. |
| Light, 375-point simulator | Sleep and its night selector were reviewed: [capture](../build/nanashi-coldglass/captures/sleep-small-light.png). This is a representative viewport check, not exhaustive accessibility certification. |
| Coach interaction | Local failure, Retry, Stop, initial latest-response positioning, explicit return to history, French follow-ups and reading older conversation during a response were exercised using synthetic local responses. No API key, paid request, external Coach provider or network success is implied. |
| Large text and keyboard | The [largest OS text setting](../build/nanashi-coldglass/captures/home-large-reviewed.png) was reviewed within the app’s existing root Dynamic Type cap; dock labels/source badge were corrected and Day actions stack. The [Coach keyboard layout](../build/nanashi-coldglass/captures/coach-keyboard.png) keeps the composer visible and hides the dock. VoiceOver labels were inspected, not a complete VoiceOver audit. |
| Identity | The [primary](../build/nanashi-coldglass/icon-primary-48.png) and [Navy](../build/nanashi-coldglass/icon-navy-48.png) icons were reviewed at 48 pixels; the primary was also inspected at 1024 pixels. |

Representative native captures: [Day](../build/nanashi-coldglass/captures/home-dark.png),
[Sleep](../build/nanashi-coldglass/captures/sleep-dark.png),
[night comparison](../build/nanashi-coldglass/captures/compare-dark.png), and
[Coach](../build/nanashi-coldglass/captures/coach-dark.png). These are synthetic-data simulator
screenshots captured during verification; a later visual correction can supersede an earlier capture.

No physical iPhone installation, Bluetooth strap test, live Coach-provider test or SideStore
change has been performed in this iteration. Historical Obsidian evidence is preserved separately
and does not prove this revision. A passing package suite alone is not an app-build or hardware test.
