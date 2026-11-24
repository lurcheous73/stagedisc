# StageDisc Privacy Policy

Effective 24 November 2026

StageDisc is a macOS app for creating disc images and, when you choose, writing to compatible optical or MiniDisc hardware. StageDisc does not require an account, show advertising, include analytics or tracking, or upload your projects and media to a StageDisc server.

## Information handled on your Mac

You choose the media, artwork, menu text, audio mixes, song titles, and release details that StageDisc uses. These can include artist and album names, copyright information, catalogue numbers, barcodes, and ISRCs. StageDisc reads the files you select and creates projects, converted media, disc images, metadata, checksums, and build reports in locations you choose. Your saved `.stagedisc` project can contain local file paths and macOS file access bookmarks. A build's project snapshot omits the bookmarks but can still contain file paths.

Release details are written to supported disc fields and to `release-metadata.json` in the build package. Depending on the format, the metadata file is also placed on the disc image. Anyone you give a disc or build package to may be able to read those details.

Build logs, command records, and factory handoff reports can contain local file paths, project details, and tool output. Please review them before sharing them with a pressing plant or in a support request.

## MiniDisc and external services

If you choose **Write album to MiniDisc**, StageDisc converts tracks in a folder you select and passes the audio files and track titles to the separately installed Control app's local NetMD helper. The transfer folder retains a release metadata file. StageDisc removes each temporary PCM track after a successful transfer; an interrupted or failed transfer can leave working files in that folder. Control is a separate app, and its own data practices are outside this policy.

StageDisc does not send app usage, project contents, or media to us. If you follow a link to GitHub or choose to report an issue there, GitHub handles the information you provide under its own privacy policy. Apple separately handles App Store downloads, purchases, and any diagnostics you choose to share with Apple.

## Storage and deletion

Projects, build packages, transfer folders, and discs remain where you create them until you delete them. You can remove local files using Finder. StageDisc may save tool path preferences locally in macOS app preferences. It has no StageDisc account or cloud copy for us to delete.

## Questions

See [StageDisc Support](SUPPORT.md) or [open a support issue](https://github.com/lurcheous73/stagedisc/issues).
