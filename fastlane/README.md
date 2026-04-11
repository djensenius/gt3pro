fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture App Store screenshots

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots to App Store Connect

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload metadata to App Store Connect

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and submit to App Store

----


## Mac

### mac upload_screenshots

```sh
[bundle exec] fastlane mac upload_screenshots
```

Upload Mac screenshots to App Store Connect

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Build and upload Mac app to TestFlight

### mac release

```sh
[bundle exec] fastlane mac release
```

Build and submit Mac app to App Store

----


## visionos

### visionos upload_screenshots

```sh
[bundle exec] fastlane visionos upload_screenshots
```

Upload Vision Pro screenshots to App Store Connect

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
