# dvdauthor and spumux source for StageDisc 1.0 (5)

StageDisc 1.0 (5) bundles the `dvdauthor` and `spumux` executables from the
macOS Sonoma arm64 Homebrew `dvdauthor` 0.7.2 revision 4 bottle. Both programs
are licensed under GNU GPL version 2 or later. The complete upstream source is
in `dvdauthor-0.7.2.tar.gz`; its SHA-256 is
`3020a92de9f78eb36f48b6f22d5a001c47107826634a785a62dfcd080f612eb7`.
The archive includes `COPYING`, the Autotools build scripts, source files,
headers, and documentation. `dvdauthor.rb` is the exact formula embedded in
the bottle used for the app.

The formula obtains that source from
<https://downloads.sourceforge.net/project/dvdauthor/dvdauthor-0.7.2.tar.gz>
and builds with `./configure`, `make`, and `make install`. Its build inputs are
`pkgconf`, FreeType, libdvdread, libpng, and macOS libxml2. To rebuild using
Homebrew, install those inputs and run `brew install --build-from-source
./dvdauthor.rb` with a Homebrew version that accepts local formula files.
Alternatively, extract the source archive and run its `./configure` script,
then `make` and `make install` using the dependencies specified by the formula.

The StageDisc packaging process copied the two arm64 executables out of the
bottle. In `spumux`, it changed two dynamic library install names:

```
install_name_tool -change '@@HOMEBREW_PREFIX@@/opt/libpng/lib/libpng16.16.dylib' '@executable_path/../lib/libpng16.16.dylib' spumux
install_name_tool -change '@@HOMEBREW_PREFIX@@/opt/freetype/lib/libfreetype.6.dylib' '@executable_path/../lib/libfreetype.6.dylib' spumux
```

The helper executables were then signed for the app distribution. The bottle
and bundled executables have matching Mach-O UUIDs: `dvdauthor`
`0FE4B6FA-31B2-389F-8BFE-D86DDDED9443` and `spumux`
`1AA9BE5C-AEA2-3A40-8184-16871DCCCC1A`. The code-signing and install-name
changes explain why the full file hashes differ.
