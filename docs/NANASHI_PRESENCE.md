# Nanashi: floating navigation and foreground observations

This revision is an Apple client preview. It does not change stored measurements, analytics,
Bluetooth commands, application identities, HealthKit permissions or the SideStore installation.
Android calculations and backup formats are unchanged; the new optional presentation is Apple-only.

## Navigation

- Activity places its existing 21st Pill Morph Tabs rail over the scroll viewport. Only its two root
  pages reserve the measured rail height in scrolling content; detail pages and sheets do not.
- Non-Coach tabs overlay the dock and reserve its measured height in the scroll content itself,
  including any active-session bar. This avoids safe-area propagation gaps across TabView and
  NavigationStack. Coach retains its existing composer/keyboard reservation.
- Visited Activity sections, filters, routes and six startup type-erasure boundaries remain intact.

## Foreground observations

`NanashiPresenceEngine` owns one cancellable batch for all page slots. It is separate from the Coach
transcript. `NanashiAside` adapts the icon/title/body/dismissal structure of
[Announcement Banner by @cnippet-dev](https://21st.dev/@cnippet-dev/components/announcement-banner),
demo 23625, to the existing native Cold Glass surface. Source, demo and preview were retrieved and
reviewed; the source is cached in `.21st/cache/component-23625.json`.

Automatic observations require a separate default-off opt-in, the Coach master switch, data consent
and a configured provider. Requests use the user's selected provider/model. The payload contains the
compact measured-day summary and recent workouts, not the transcript, raw sensor streams, optional
on-device analysis or chart images. The model chooses a few scenes with sufficiently specific
evidence; no observation is required for a scene. Output is validated before display.

The tone is direct, dry and sarcastic about choices and contradictions. Instructions prohibit
invented measurements, medical diagnosis, body-shaming and unsafe prescriptions. As with any model
output, factual accuracy and tone remain model-dependent; instructions are not a factual verifier.
Observations identify their snapshot and must date older measurements rather than imply they are
current. Reading an old night does not cause an observation to pretend it analysed that selected night.

One request supplies multiple scenes, at most four attempts per local day, at least thirty minutes
apart, with a fifteen-minute failure backoff. Failures/cancellations consume an attempt. These limits
survive relaunch and clock rollback. Generated text expires after six hours. A protected, backup-excluded local cache preserves a dated
batch across launches for the same provider, model, language, device, day and connection epoch.
Consent or connection changes retire it. Measurement updates label the retained snapshot as an
earlier analysis while the request allowance remains in force; they do not erase it during sync. Dismissed scenes
stay quiet for the app session. Existing data remains usable on failure; pages do not show error spam.
There is no background job, notification, global overlay or per-scroll request. The visible host
suspends work when the app becomes inactive, and concurrent hosts share a single request.

The explicit simulator `--demo-coach` mode uses labelled local French fixtures without any provider
request. Its opt-in is ephemeral and cannot become a production consent grant. Demo observations do
not validate the quality of a real model's generated advice.

## Provider catalogue

Official documentation was reviewed on 2026-10-27:

- [OpenAI models](https://developers.openai.com/api/docs/models) and
  [model listing](https://developers.openai.com/api/reference/resources/models/methods/list).
- [Claude models](https://platform.claude.com/docs/en/models/overview) and
  [paginated model listing](https://platform.claude.com/docs/en/api/models/list).
- [Gemini models](https://ai.google.dev/gemini-api/docs/models) and
  [model listing](https://ai.google.dev/api/models).

Offline suggestions are updated. Opening Coach settings refreshes a catalogue older than 24 hours;
manual refresh remains available. The last successful timestamp is visible. Complete paginated lists
replace suggestions, while errors preserve the previous catalogue. The selected model is retained
even if missing from the latest list, with a note. Listing is not a guarantee of account quota or
endpoint access. Known incompatible, specialized or retired entries are filtered where identifiable.
Anthropic one-shot responses now collect visible text after reasoning blocks.

## Verification boundary

Policy, engine, consent/configuration races, provider request shapes, parsing and catalogue pagination
are covered by synthetic fixtures. Tests use injected key/workout readers and intercepted HTTP rather
than personal credentials or the real local database. Final build and simulator results are recorded
in `build/nanashi-coldglass/` and the Cold Glass delivery log. No physical-device behavior or real
provider response is implied by simulator/fixture success.

## Completed checks — 2026-10-27

- Final iOS simulator build: `build/nanashi-coldglass/ios-presence-delivery.log`.
- Final macOS build: `build/nanashi-coldglass/mac-presence-delivery.log`.
- 108 selected app test methods passed with zero failures:
  `build/nanashi-coldglass/mac-presence-final.log`.
- Translation audit passed: `build/nanashi-coldglass/i18n-presence-final.log`.
  Source-comment lint and diff whitespace checks also passed.
- Activity's 30-day filter survived a Trends round-trip. The floating rail was reviewed both at
  the initial position and over scrolled content. Explorer's final Settings row clears the dock.
  Inline observations, dismissal, the optional setting and the model picker were exercised.
- Small-screen review used a 375×667 simulator in light appearance with large text, alongside the
  iPhone 13 simulator in dark appearance. The small simulator was shut down after review.

Capture evidence is in `build/nanashi-coldglass/captures/`: `activity-floating-scroll.png`,
`explorer-bottom-fixed.png`, `explorer-small-large-light.png` and `activity-presence-final.png`.
End positions were reached using the explicit DEBUG-only `--demo-scroll-bottom` fixture because
CUA gesture dispatch was unavailable. This verifies layout clearance, not manual swipe behavior.
The delivered preview runs without that argument. Live provider quality, physical-device Bluetooth
and physical-device installation were not tested or changed in this revision.

## Authorized iPhone delivery — build 443

After the preview, the user requested installation. Build 443 compiled for physical iOS and was
installed through the existing SideStore record as an in-place update from build 441. Both app and
widget retain their original source bundle identities and capability templates. No uninstall,
identity transfer, credential extraction or renewal-automation change was performed.

A fresh private local backup of Library, Documents and the shared group was taken before delivery.
SQLite integrity passed before and after the update. No table row counts decreased; new sensor
records arrived after launch. Coach preferences and the HealthKit identity marker were retained.
The installed build, SideStore success log and continuing app process were verified. Device Hub
could not display the physical screen while the phone microphone or camera was active, so this
is not a visual end-to-end phone review or a live-provider response test. Delivery evidence:
`build/nanashi-coldglass/install-443/status.json` and `iphone-build.log` in that directory.

## Fluency and setup correction — build 444

The dock is now a single persistent shell overlay. Its selection indicator animates locally while
native tab contents switch without a whole-page spring. Glass geometry is no longer torn down with
each tab, and rounded height feedback does not inherit animation. Automatic minimization stops
measuring scroll position entirely when the preference is off. The six startup type-erasure
boundaries and existing tab/route identities remain.

Presence rendering uses connection/data revisions instead of formatting the biometric summary.
Credential-availability metadata is cached per connection; secrets are never cached and requests
still resolve the actual Keychain value and owner. Foreground re-entry invalidates availability.
Repeated idle suspension does not publish view changes, synchronization events are coalesced, and
optional generation waits briefly for navigation to settle. App-level scene handlers own background
cancellation, including when Coach has replaced the page that first started the request.

Day and Workouts reuse completed, unchanged presentation reads for quick revisits (at most 30 seconds).
Explicit refresh and data/input changes bypass reuse. Request tickets prevent cancelled or superseded
reads from overwriting another day's presentation. Stored data and physiological formulas are unchanged.

The Coach exposes one **Remarks in the app** control, also first in its settings. Model and advanced
controls are collapsed. Missing data consent requires an explicit named-provider confirmation;
existing credentials, model choice and permissions are retained. New copy is translated into all ten
existing locales.

Verification: 70 selected application tests passed in `build/nanashi-fluency/mac-tests-delivery.log`;
the simulator build passed in `ios-sim-final.log`. Eight tab changes retained the same dock accessibility
elements, the remarks switch was exercised off/on, and keyboard appearance hid the dock while keeping
the composer visible. Captures: `coach-settings.png`, `coach-keyboard.png`; recorded sequence:
`navigation-after.mp4`, all in that directory. These checks used synthetic simulator data. Instruments
could not attach to the simulator process, so no measured physical-device frame-rate claim is made.


## Authorized iPhone delivery — build 444

The physical iOS Release build passed in `build/nanashi-fluency/iphone-release-444.log`.
SideStore signed and installed build 444 as an in-place update to the existing suffixed app identity.
Installation took approximately 105 seconds after signing; the completed SideStore operation and
installed bundle version were checked rather than treating the initial reported alert as a failure.
No retry, uninstall, credential reset or identity transfer was needed.

A fresh private stable snapshot was verified before installation. After normal launch, a second
stable snapshot passed SQLite integrity verification: none of 36 table counts decreased, and no
historical primary keys were missing from daily metrics, sleep sessions, conversations, live sessions,
journal entries or paired devices. The seven existing Coach preferences and the HealthKit identity
marker remained unchanged. The application was resumed after the brief verification suspension.
The existing SideStore renewal automation and system permissions were not modified.

Physical-device tab fluidity and a live-provider response have not been independently exercised in
this delivery. The microphone/camera screen-sharing restriction remains a review limitation.
Delivery evidence is recorded in `build/nanashi-fluency/status.json`; sensitive snapshots and device
logs remain outside the repository.


## Interaction correction — build 445

Day navigation now presents the native seven-column calendar in a viewport-sized iPhone sheet,
using the existing Drawer adaptation. The forced compact popover was removed; shared DayNavBar
uses the same presentation. Date-offset and logical-day calculations remain unchanged.

Coach uses a compact floating glass composer, with text, microphone and Send/Stop in one row.
Its measured height reserves space at the end of the transcript; keyboard safe areas and the
shell's dock reservation remain independent. An inline observation's action prepares a follow-up
in Coach, preserving an existing draft and requiring the user to send it.

A dated presence batch no longer disappears or gets cancelled every time sync updates a metric.
Access identity and measurement revision are separate. Earlier snapshots are labelled, a valid
general observation can serve pages without a specific observation, and the protected local cache
avoids spending another request merely to reopen the app. Provider/consent gates, daily allowance,
foreground-only generation and dismissal remain enforced. No schema or physiological change is made.

Rendering boundaries avoid rebuilding unrelated page factories on shell chrome changes. Sleep and
Trends now defer their section factories inside real lazy stacks, and retain completed unchanged
presentation reads on quick revisits. Explicit refresh and changed inputs bypass reuse.

Validation for this revision is recorded in `build/nanashi-interaction/`:

- The final simulator build passed in `ios-sim-keyboard-final.log`.
- 99 targeted macOS application tests passed with zero failures in `mac-tests-delivery.log`.
  A subsequent 31-test run passed with zero failures in `mac-tests-keyboard-final.log`, covering
  Coach scroll following/state races and sleep comparison/result changes. These separate runs
  are not a claim of 130 distinct test methods.
- The calendar showed seven readable columns on the dark iPhone 13 simulator and a 375×667
  light simulator with large text. Cancel retained the selected day. Captures are
  `captures/calendar-iphone13.png` and `captures/calendar-small-light-large.png`.
  After restoring the simulator input relay, selecting 24 October dismissed the sheet and
  displayed Saturday 24 October (`captures/calendar-selection-final.png`). Existing date-offset
  and logical-day tests passed.
- The compact floating composer and expanded prepared draft were reviewed in simulator captures.
  The inline observation action prepared a Coach draft without sending a chat message. Final
  keyboard review passed after restoring the simulator input relay: the full final paragraph and
  privacy note clear the composer in `captures/coach-keyboard-final.png`. Scrolling toward older
  messages revealed Latest Response. Hiding and reopening the keyboard retained the Coach heading
  and first older message instead of forcing the transcript to the bottom.
- A simulator tab round-trip retained the selected 25–26 October sleep night and its 6 h 56 min
  duration after visiting Activity. Activity retained its Trends section; its Sessions section
  retained the 30-day filter after returning.
- Source-comment lint and diff whitespace checks passed. No physical-device frame-rate measurement
  was obtained, and synthetic simulator observations do not verify live-provider response quality.

The final physical Release build passed in `iphone-release-final-445.log`. The app and widget
capability template and ad hoc signatures were verified for build 445, preserving their source
identities. A fresh private database snapshot passed SQLite integrity checking across 36 tables.
Package 445 was transferred and its SideStore import opened; installation confirmation is pending.
Delivery is tracked separately in the local status file. An import is not installation confirmation;
compilation, simulator interaction and physical-device behavior remain separate evidence.
