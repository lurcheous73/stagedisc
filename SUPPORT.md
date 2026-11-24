# StageDisc Support

StageDisc runs on Apple Silicon Macs with macOS 14 or newer. It creates test outputs for DVD-Video, Red Book CD audio, DVD-Audio, and Blu-ray video or audio. You can import media, design menus, add release metadata, and choose where to save each build.

For help or to report a problem, [open a StageDisc issue on GitHub](https://github.com/lurcheous73/stagedisc/issues/new). You can read [existing issues](https://github.com/lurcheous73/stagedisc/issues) without a GitHub account; posting an issue requires one. Include the StageDisc version, macOS version, chosen disc format, what you tried, and the exact error message.

## Common questions

- **Where is my output?** StageDisc creates a dated folder inside the build location you chose. Use **Reveal output** in **Build & test** to open it in Finder.
- **Why can't I write a MiniDisc?** Install Control.app in `/Applications`, connect a compatible NetMD recorder, and insert a writable MiniDisc. StageDisc uses Control's local writer for standard play (SP) transfers.
- **Why won't DVD-Audio build?** Check that the selected audio files can be read and that the chosen build folder has enough free space. Open the build log for the exact authoring error and include it when requesting help.
- **Can StageDisc burn a CD?** CD audio builds produce `disc.bin` and `disc.cue`. Writing them requires a CD-DA capable writer. DVD and Blu-ray image burning requires a compatible optical burner and media.
- **Is Blu-ray Audio Pure Audio certified?** StageDisc creates a Blu-ray audio test package with artwork, chapters, and menu controls. Physical playback, Pure Audio certification, and manufacturing acceptance require independent review.
- **Should I test the disc before pressing?** Yes. Check the image and final disc on the players you intend to support, then obtain the mastering plant's approval before replication.

## Sharing diagnostic files

The build folder contains `build.log`, `commands.json`, `release-metadata.json`, and other reports. These can reveal local file paths and release details. Remove private information before attaching them to a public issue. Do not post source media or a `.stagedisc` project publicly unless you intend to share its content and file paths.

Read the [StageDisc Privacy Policy](PRIVACY.md) for details about local files and MiniDisc transfer.
