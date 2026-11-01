# SpektraCam

**Version 0.1.1**

SpektraCam is a photo editor for iPhone.
It has a local library for imported photos.
It uses a native port of [spektrafilm](https://github.com/andreavolpato/spektrafilm/tree/3bb2c2d2801ff68b92019cf1dbcbb133d60832bc) by Andrea Volpato.

The app uses a portrait interface.
It has Crop, Develop, Adjust, Effects, and Export controls.
It saves processed JPEG and PNG files to Photos.
It also has the system share sheet.

Import from Photos or Files. Photos appear in capture-date order, with the newest capture dates at the bottom.
The library has RAW and Rendered filters. Tap a photo, then tap Develop.
The app keeps the original file and saves edits as a versioned recipe.
Editing uses a floating-point preview at 1080 px on the long edge. Export can use the original resolution.
Thumbnails and previews can be rebuilt. Delete removes only the app copy and its edits.
Camera capture is not available yet.

Version 0.2 is planned for RAW camera capture.

## Build

Requirements: Xcode 27.2, iOS 27.2 or later, and Python 3 for the test scripts.

1. Open `andreavolpato-spektrafilm.xcodeproj` in Xcode.
2. Select an iPhone Simulator.
3. Run the app.

For device tests, select your Apple Developer team.

## Code map

Folders in Xcode match the folders on disk. See [Apple's folder guide](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project).

| Folder | Contents |
| --- | --- |
| `App` | App start and root view |
| `Features` | Library, Viewer, Editor, and Export |
| `Shared` | Reused views and photo badges |
| `Models` | Edit recipe, profiles, and metadata |
| `Rendering` | CPU and Metal processing |
| `Resources` | Assets, profiles, tables, and shaders |

Start with `App/ContentView.swift`. Open `Features/Viewer` for the photo view or `Features/Editor` for editing controls.

## Tests

Run the native tests:

```sh
python3 Scripts/core-checks.py
```

For UI tests, add two different rendered photos to the Simulator photo library.
UI tests use a separate app library. They do not reset the user library.
Run the UI tests:

```sh
python3 Scripts/build-and-run.py --ui-tests
```

The pinned Python reference has 189 passed tests and four known test failures.
The native tests use the reference data in `Reference/Fixtures`.

## Next work

Complete performance tests on a physical iPhone.
Decrease memory use for large RAW exports and diffusion.
Validate genuine iPhone and Indigo DNG files.
Complete these checks before the version 0.2 release.

Current export format: SDR, sRGB, 8-bit.

## License

[GPLv3](LICENSE) applies to the code.
[CC BY-SA 4.0](SPEKTRAFILM_LICENSE.txt) applies to profile and LUT data.
Keep the license files and [third-party notices](ThirdPartyNotices.txt).

## Project text

Use [ASD-STE100](https://www.asd-ste100.org/about_STE.html) for project text and commit messages.
Keep commit messages short.
