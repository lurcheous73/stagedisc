# Beta verification — 6 October 2026

Candidate: **StageDisc 1.0 (3)**, native macOS archive, Apple Silicon, minimum macOS 14. Xcode 27 / macOS 26 development host. The archived app has the matching App Store Connect bundle ID, App Store sandbox, inherited helper entitlements and a privacy manifest. `codesign --verify --deep --strict` passes. Non-exempt encryption is false.

## Passed

- Native Xcode app/framework build and signed macOS archive. All four CLI media/disc helpers are rebuilt for macOS 14, bundled and link only system libraries/frameworks. Their matching dSYMs are included in the final archive; helper UUID checks pass. No Homebrew or desktop Java runtime is needed by the app.
- 12 source tests cover invalid chapters/timecodes, forbidden HDR conversion/UHD encoding, pagination reachability, lossless copy commands, channel/rate validation, fingerprint changes, UHD index preservation and a known SHA-256 digest. All pass.
- Synthetic standard Blu-ray concert with song chapters, multiple audio tracks and an extra; experimental prepared-video UHD with a bonus title; audio album with artwork video and five distinct mixes. All build through the shared native authoring core with bundled FFmpeg 8.0.
- Independent libudfread extraction matches every disc-tree file in the final ISOs: 19 concert files, 19 UHD files and 14 album files.
- Final album transport stream contains H.264, 5.1 LPCM at 24/96, stereo LPCM at 24/192, AC-3 5.1, DTS 5.1 and TrueHD 5.1 with a recognised AC-3 compatibility core.
- LPCM decoded from M2TS is byte-identical to the prepared PCM: 10,368,000 bytes for six channels at 96 kHz and 6,912,000 bytes for stereo at 192 kHz. Individual channel hashes match.
- Prepared DTS and combined TrueHD+AC-3 are copied byte-identically. Independent transport packet extraction confirms all 7,200 TrueHD packets (1,835,996 bytes) and 188 AC-3 core packets (481,280 bytes) match their elementary sources. Both decode in full with identical source/transport decoded samples. Synthetic TrueHD has **no Atmos metadata**.
- VLC/libbluray loads the BD-J runtime from the ISO, initialises the raster menu, autoplays the album, selects the default mix and returns to the menu after playback in three successive runs. The synchronous menu PNG decoder matches an independent decoder pixel for pixel. This headless check observes events; it is not a visual/hardware navigation or listening test.
- Packaged beta opens its native macOS window. Security-scoped file/folder access and the sandboxed build path still need interactive beta testing.

An earlier synthetic TrueHD test exposed missing PES substream identifiers. `--new-audio-pes` now explicitly separates TrueHD and its AC-3 core. The final fixture passes independent full decode and packet equality; earlier test builds are superseded. Raster image loading now uses a synchronous PNG decoder and a standard DVB buffered image, with application-owned menu event delivery; mix selection runs after prefetch/start. Repeated playback exposed the asynchronous image-loader race before these changes.

## Unverified

- Physical burner access, writing/verification in the App Store sandbox, recordable BD layers and standalone-player navigation, resume, sync, audio switching and UHD playback. No burner is attached to the development Mac.
- Commercial DTS-HD MA, DTS:X, TrueHD Atmos, DD+ substream conformance, object/extension metadata and every channel layout. This beta copies prepared bitstreams and does not encode immersive masters.
- Pure Audio/AES-21id certification, mShuttle, licensed Dolby Vision authoring, HDR10+ validation, AACS, production disc IDs and BDCMF/UHD-BDCMF mastering.
- Factory acceptance and replicated-disc layer layout. Get written delivery requirements and test the plant's production check disc.
- The first upload was rejected for a missing app-category key; the final archive includes the Video category. TestFlight processing/review and install behaviour are separate from archive success; verify the build's state in App Store Connect.

Local test outputs, generated synthetic masters and full diagnostics stay outside Git. They contain source paths and signing details and are not production masters.
