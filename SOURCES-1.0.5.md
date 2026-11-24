# Corresponding GPL source for StageDisc 1.0 (5)

This page identifies the source for the GPL executables bundled in the macOS TestFlight build 1.0 (5).

## DVD-Audio author

The native arm64 `dvda-author` helper is built from the [StageDisc DVD-Audio source package](ThirdParty/sources/stagedisc-dvda-author-1.0.5-source.tar.gz) (SHA-256 `8e5d58e8e68a11ca1a64c6bb80a56fd99564f95f4648330f9979033d3a7413a4`). This package contains the upstream snapshot, StageDisc's modified compatibility files, original copyright notices, GPL licenses, and `Tools/build-dvda-author.sh`. Extract the package at a directory root, then run `bash Tools/build-dvda-author.sh` on an Apple silicon Mac with Xcode Command Line Tools. See `ThirdParty/dvda-author/STAGEDISC-BUILD.md` inside the package. The helper in build 1.0 (5) has Mach-O UUID `4684588A-DEB0-3786-BDCA-96C7415F0FAD`.

## DVD-Video author and menu muxer

The bundled `dvdauthor` and `spumux` come from the Homebrew Sonoma arm64 `dvdauthor` 0.7.2 revision 4 bottle. Their [complete upstream GPL source](ThirdParty/sources/dvdauthor-0.7.2_4/dvdauthor-0.7.2.tar.gz) has SHA-256 `3020a92de9f78eb36f48b6f22d5a001c47107826634a785a62dfcd080f612eb7`. The [exact bottle formula](ThirdParty/sources/dvdauthor-0.7.2_4/dvdauthor.rb), [GPL license](ThirdParty/sources/dvdauthor-0.7.2_4/COPYING), and [source and packaging instructions](ThirdParty/sources/dvdauthor-0.7.2_4/README-SOURCE.md) are alongside it.

## FFmpeg and x264

The exact FFmpeg and x264 sources are in [`ThirdParty/sources`](ThirdParty/sources), with checksums in [`manifest.json`](ThirdParty/sources/manifest.json) and the configuration in [`Tools/build-media-tools.sh`](Tools/build-media-tools.sh).

The StageDisc application source is in this repository under its MIT license. Each third-party program keeps its own license and copyright notices.
