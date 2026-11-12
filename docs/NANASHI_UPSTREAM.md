# Nanashi upstream integration

Upstream: https://github.com/ryanbr/noop

- Previous base: `e58017508d9731c51d0631fe0eb4bb1d7ea0c582`.
- Integrated main: `2a1de7609843b095505274ad6fc811757210be80` (24 commits).
- Latest published upstream release at verification: `v12.0.0`, older than the base.
- Nanashi publishes version 12.1.1, with independent iOS 446 and Android 559 build counters.

The integration retains the upstream Swift/Kotlin analytics changes together,
including Banister calibration and ECG waveform schema migrations. It adopts the
shared night-heart-rate chart while preserving Nanashi's historical-night state.
BLE fixes are included from upstream; compilation and unit tests do not establish
real strap connection behavior.

Nanashi changes are committed independently from the merge, preserving upstream
history. Generated Xcode projects, private databases, signing material and build
products remain excluded from Git. The Firebase release catalogue and website are
fork-specific distribution services, not upstream NOOP services.
