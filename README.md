# StageDisc for macOS

A native SwiftUI app for preparing concert and audio album Blu-ray test discs: branded BD-J menus, song chapters, extras, multiple mixes, UDF 2.50 images, burn commands and a report tied to the exact tested build. Apple Silicon, macOS 14 or newer.

## Use

1. Choose **Concert film & extras** or **Audio album & bonus content**, then import your continuous main master and any bonus titles.
2. In **Media & audio**, add embedded or separate audio mixes. Label, reorder, choose a format, language and sync offset. The first mix is the playback default. Enter song chapters as `HH:MM:SS.mmm | Song name`; the first starts at zero.
3. Design the band menu in **Disc menu**. Arrow/Enter navigation, songs, extras and audio mixes are included in the on-disc menu. Audio album mode can autoplay; coloured remote buttons select the first four mixes. Use a continuous album master plus chapters to avoid gaps introduced by separate playlists.
4. Save your `.stagedisc` project and choose a build folder. **Build & test** creates an isolated dated build, BDMV folder and test ISO. Long films can take hours to encode.
5. Burn to recordable media and test standalone players. Record menu, song seek, audio mix, sync, extras and return behaviour against that exact build. Check the plant's accepted delivery format before preparing **Factory handoff**.

The app bundles FFmpeg, FFprobe, tsMuxer and its UDF writer. Homebrew and Java are unnecessary for authoring. App Store builds use only bundled tools and security-scoped access to folders you select. Local source builds can use custom tools.

## Audio

| Output | Behaviour |
| --- | --- |
| LPCM | 16-bit/48 kHz or 24-bit/48, 96, 192 kHz; preserves channel count. Up to 8 channels at 48/96 kHz, up to 6 at 192 kHz. |
| Dolby Digital | AC-3 at 640 kb/s; mono, stereo or 5.1. No implicit downmix. |
| DTS / DTS-HD | Copies prepared elementary masters or container audio without a down-to-DTS filter. HD extensions and DTS:X require independent verification. |
| TrueHD / TrueHD Atmos | Copies a prepared **interleaved TrueHD+AC-3 elementary master** intact. Bare TrueHD and extraction from MKV are blocked because they omit disc compatibility audio. Atmos presence is not inferred from the channel count. |
| DD+ / E-AC-3 | Experimental prepared bitstream copying; Blu-ray substream structure needs external verification. |
| WAV, AIFF, FLAC, CAF, AAC and other decodable inputs | Import as source material and convert to LPCM or AC-3. They are not all Blu-ray delivery codecs. |

There is no DTS-HD, TrueHD, Atmos or DTS:X encoder. Supply an externally encoded delivery master for those formats. Conversion to PCM/AC-3 retains channel audio and removes immersive metadata. No loudness processing is applied. Manual sync offsets and duration checks do not replace player testing.

Audio album mode supplies a low bitrate artwork video, menus, song chapters, autoplay and remote mix selection. Pure Audio/AES-21id conformance is **unverified**; this beta does not implement mShuttle or claim Pure Audio certification.

## Picture and disc scope

- H.264 1920×1080, 8-bit SDR encoding at 23.976, 24, 25 or 29.97 fps. x264 uses Blu-ray compatibility settings; 25/29.97 use fake-interlaced signalling. Aspect ratio is preserved with letterboxing/pillarboxing.
- Copy prepared H.264 for standard Blu-ray, or experimental 3840×2160 HEVC Main 10 for UHD. UHD encoding and SDR/HDR conversion are blocked. Copied HDR metadata still needs external conformance and player verification.
- Static branded BD-J menus, main-title chapters, extras and per-title mixes. Playback keys support play, pause, stop and chapter navigation. No subtitles, moving menus or extra-specific song menus.
- UDF 2.50 ISO, checksums, cancellation, capacity/transport budgeting and a factory report. Altered images/disc trees are rejected when updating a handoff report.
- Burn uses macOS `hdiutil` verification/finalisation. No burner is attached to the development Mac: hardware writing and the App Store sandbox's optical-drive access are unverified.

## Factory pressing

A test ISO is **not a BDCMF or UHD-BDCMF production master**. StageDisc does not provide AACS, licensed Dolby Vision authoring, production disc IDs, replicated layer layout approval or a full conformance certificate. A mastering service may accept ISO/BDMV and convert it. Obtain written plant acceptance and test its final check disc before approving pressing.

The app writes development disc/organisation IDs. The mastering facility must assign production IDs. Software playback and ISO readback do not establish standalone-player or pressing compatibility.

## Build

Use Xcode with the shared **StageDisc** scheme in `StageDisc.xcodeproj`. Debug is a local app; Release enables the App Store sandbox. The bundle ID matches the StageDisc listing: `uk.brimstonecottage.stagedisc`. Set your own development team locally. No signing credentials belong in this repository.

```sh
swift test
bash Tools/build-app.sh /absolute/path/to/StageDisc-preview.app
```

`Tools/generate-xcode-project.py` regenerates the native app/framework targets. `Tools/build-media-tools.sh` rebuilds the static FFmpeg/x264 helpers from the exact source archives under `ThirdParty/sources`; it needs a compiler, make and pkg-config. `Tools/generate-icon.swift` generates the original icon PNGs. Bundled binaries are Apple Silicon; Intel distribution requires matching rebuilt tools.

To rebuild the disc tools with matching debug symbols:

```sh
STAGEDISC_SYMBOLS_DIR=/absolute/path/to/symbols bash Tools/build-disc-tools.sh
```

To rebuild the UDF writer alone:

```sh
cmake -S Tools -B /tmp/stagedisc-udf -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build /tmp/stagedisc-udf
cp /tmp/stagedisc-udf/stagedisc-udf Resources/bin/
```

Rebuilding `Tools/StageMenu.java` requires a BD-J API classpath and an Eclipse compiler with Java 1.4 language support. `MenuPackager.java` generates the precompiled BDJO template; its desktop Java dependency is not needed during authoring. Original headers and licence notices are in `ThirdParty`. See [THIRD_PARTY.md](THIRD_PARTY.md).

The CLI uses the same core:

```sh
stage-disc-cli probe film.mov --resources /absolute/path/to/Resources
stage-disc-cli demo demo.stagedisc concert.mp4 extra.mp4 --resources /absolute/path/to/Resources
stage-disc-cli check demo.stagedisc --resources /absolute/path/to/Resources
stage-disc-cli build demo.stagedisc /absolute/path/to/builds --resources /absolute/path/to/Resources
```

## Beta release

`Tools/testflight-macos.sh` archives and exports/uploads for macOS with the existing Xcode account, or an optional App Store Connect API env file outside the repository. It requires working Mac App Distribution / Mac Installer Distribution signing and `STAGEDISC_SYMBOLS_DIR` containing matching helper dSYMs. Both tool build scripts can write to that folder; `Tools/verify-helper-symbols.py` rejects stale symbols before upload. Upload completion and Apple processing must be verified in App Store Connect; an archive alone is not an upload.

This beta has meaningful source tests, synthetic disc builds and software checks. Physical navigation/burns, commercial Atmos/DTS-HD/X masters, UHD players and production mastering remain unverified. See [VERIFICATION.md](VERIFICATION.md).
