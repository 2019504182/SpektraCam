# SpektraCam

**Version 0.2.1**

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
The library uses cached 384 px thumbnails and shares render resources when it rebuilds them.
Editing uses a floating-point preview at 1080 px on the long edge. Export can use the original resolution.
Thumbnails and previews can be rebuilt. Delete removes only the app copy and its edits.

## RAW camera and LUTs

It captures DNG only and offers Apple ProRAW or Bayer RAW when available.
Lens buttons use physical cameras at their native focal lengths.
Tap the viewfinder to focus and meter. Use the vertical slider to adjust camera exposure.
It has a preview histogram, exposure readout, grid, and shutter and completion haptics.
Captured DNG files stay in a recovery inbox until library import succeeds.
The DNG menu offers maximum native resolution when the selected lens supports it.
Optional When In Use location access adds capture coordinates to the DNG.
Capture also works without location access.
Simulator shows an unavailable state; it cannot capture photos.
Stop Device Hub's View Screen before using the physical camera.
Apple blocks camera access during Device Hub interaction.
The camera's Library button returns to the main library. Close returns to the previous screen.

RAW dimensions come from the RAW decoder, not the embedded preview.
The app repairs old library entries that used preview dimensions.
The app icon uses Runze Ni's Icon Composer file. Its source vectors are in `Design/Icon`.

Develop has two 3D `.cube` LUT slots with separate Mix controls.
Use LUTs made for encoded sRGB photos. Log and HDR input transforms are not supported.
RAW photo-LUT input uses the system decoder's default rendering. Film input stays scene-linear.
The library LUT Manager shares import, rename and batch deletion with the editor picker.
Normal deletion protects LUTs used by saved edits or Undo. Confirmed Force Delete clears their references and keeps other adjustments.
LUT mode skips film/print color. Halation and diffusion act on linear RGB before the LUTs.
A Portra 400 grain noise layer follows the LUTs.
It restores the sharp density image before print/scan conversion to reduce false grain at highlight edges.
These effects are an RGB adaptation. They do not form a full spectral emulsion model.

Halation Amount ranges from 0 to 20×. The stock default remains 1×.
Scatter is a 0–100% light mixture, with a default of 100%.
Physical effect radii use micrometres. Grain Blur uses working-image pixels, as in the pinned source.

Exposure, S-curve, pivot, highlights, shadows, white balance and saturation precede Develop.
Processing keeps floating-point headroom until the final SDR conversion.

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
| `Features` | Library, Viewer, Editor, Export, Camera, and LUT |
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

Set `SPEKTRACAM_SIMULATOR_ID` to select a booted test Simulator.
Test two local LUTs without adding them to the repository:

```sh
python3 Scripts/core-checks.py lut preview --input /path/first.cube /path/second.cube
```

The pinned Python reference has 189 passed tests and four known test failures.
The native tests use the reference data in `Reference/Fixtures`.

## Changes in 0.2.1

Add native LUT reorder and confirmed force deletion. Keep photo adjustments when a LUT is removed.
Fix HEIF gain-map brightness in SDR LUT mode, saved shadow edits, photo paging and crop panning.
Add signed S-curve controls: zero is neutral; positive increases contrast. New adjustments use −0.35…+0.35. Older curve versions remain readable.
Use a compact 2500–8000 K RAW slider, with wider numeric entry and as-shot reset.
Raise the export sheet and show its dimensions above the fixed actions. Add an explicit memory-warning override.
Process full-size LUT grading in strips. Normal 12 MP RAW and LUT exports pass on iPhone 15 Pro Max.
Extreme full-size diffusion can still exceed device memory and terminate the app, including with the override.

## Next work

Complete the physical-device test matrix, including Max resolution and interruptions.
Decrease memory use for large RAW exports and diffusion.
Validate genuine iPhone and Indigo DNG files.

Current export format: SDR, sRGB, 8-bit.

## License

[GPLv3](LICENSE) applies to the code.
[CC BY-SA 4.0](SPEKTRAFILM_LICENSE.txt) applies to profile and LUT data.
Keep the license files and [third-party notices](ThirdPartyNotices.txt).

## Project text

Use [ASD-STE100](https://www.asd-ste100.org/about_STE.html) for project text and commit messages.
Keep commit messages short.
