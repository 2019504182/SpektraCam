# SpektraCam

**Version 0.1.0 · Development version**

SpektraCam is a photo editor for iPhone.
It uses a native port of [spektrafilm](https://github.com/andreavolpato/spektrafilm/tree/3bb2c2d2801ff68b92019cf1dbcbb133d60832bc) by Andrea Volpato.

The app uses a portrait interface.
It has Crop, Develop, Adjust, Effects, and Export controls.
It saves processed JPEG and PNG files to Photos.
It also has the system share sheet.

## Build

Requirements: Xcode 27.2, iOS 27.2 or later, and Python 3 for the test scripts.

1. Open `andreavolpato-spektrafilm.xcodeproj` in Xcode.
2. Select an iPhone Simulator.
3. Run the app.

For device tests, select your Apple Developer team.

## Tests

Run the native tests:

```sh
python3 Scripts/core-checks.py
```

For UI tests, add a local photo to the Simulator photo library.
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
Complete this work before version 0.2.0.

Current export format: SDR, sRGB, 8-bit.

## License

[GPLv3](LICENSE) applies to the code.
[CC BY-SA 4.0](SPEKTRAFILM_LICENSE.txt) applies to profile and LUT data.
Keep the license files and [third-party notices](ThirdPartyNotices.txt).

## Project text

Use [ASD-STE100](https://www.asd-ste100.org/about_STE.html) for project text and commit messages.
Keep commit messages short.
