# Third-party components

StageDisc application, menu runtime, icon and adapter code: MIT, see LICENSE.

## tsMuxer 2.7.0

Source: https://github.com/justdan96/tsMuxer, tag 2.7.0, commit `f06ac394c55ccee1cb76ae54f4636532a2d10253`.
Apache License 2.0, reproduced in ThirdParty/tsMuxer/LICENSE and Resources/LICENSE-tsMuxer.txt. Original notices remain in the source. The CLI binary is rebuilt from this exact source with a macOS 14 deployment target and matching debug symbols. The StageDisc UDF adapter links its ISO writer unchanged. Both the original implementation and adapter source are supplied.

## FFmpeg 8.0 with x264

FFmpeg source: https://github.com/FFmpeg/FFmpeg, tag n8.0, commit `140fd653aed8cad774f991ba083e2d01e86420c7`.
x264 source: https://code.videolan.org/videolan/x264, commit `b35605ace3ddf7c1a5d67a2eb553f034aef41d55`.

The bundled FFmpeg/FFprobe helpers statically link x264, making these helpers GPL version 2 or later. Their exact corresponding source archives, retained original notices and SHA-256 manifest are in `ThirdParty/sources`. Full reproducible configuration is in `Tools/build-media-tools.sh`; no nonfree option is enabled. Copies of both GPL notices are bundled in `Resources`. Helpers run as separate command-line programs. They link only macOS system libraries/frameworks, including zlib. No Homebrew runtime is required. Source is available at https://github.com/lurcheous73/stagedisc.

## HD Cookbook BDJO tools / BitStreamIO

Source: HD Cookbook sources from https://github.com/cheeseb1234/auto-bluray-tui, which retains historical Sun Microsystems BSD licence headers. Only BDJO classes and BitStreamIO are used. Original copyright, redistribution conditions and disclaimers are retained in ThirdParty/HD-Cookbook and Resources/LICENSE-HD-Cookbook.txt. These generated the bundled BDJO template. The on-disc StageMenu runtime is original MIT StageDisc code.

## Development-only dependencies

Java, Eclipse ECJ and BD-J API stubs are used to rebuild the menu tools. They are not distributed as runtime dependencies in StageDisc.app. libudfread and VLC/libbluray are independent development verification tools and are not bundled.

Open-source copyright licences do not supply codec patents, trademark rights, disc-format certification or a commercial mastering service. StageDisc does not certify Atmos, DTS:X, Pure Audio or factory acceptance. Apple distribution approval is a separate process.
