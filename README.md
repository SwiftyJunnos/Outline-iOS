# Outline iOS

Read this in [한국어](README.ko.md).

An unofficial iOS client for Outline servers. Read documents stored in Outline on iPhone and iPad.

Outline: <https://www.getoutline.com>

## Screenshots

| Connection | Document list | Document reader |
| --- | --- | --- |
| ![Connection](Screenshots/connection.png) | ![Document list](Screenshots/documents.png) | ![Document reader](Screenshots/document.png) |

Screenshots are placeholders — replace them with actual device captures later.

## Requirements

- iOS 17.0 or later
- An Outline server (self-hosted or Outline Cloud)

## Build

1. Open `Outline.xcodeproj` in Xcode.
2. Select a simulator or device.
3. Build and run with `Cmd + R`.

## Connecting to an Outline server

On first launch, enter your Outline server URL and an API key.

1. In your Outline server settings, go to **API Keys** and create a read-only API key.
2. In the iOS app, enter the server URL (for example `https://outline.example.com`) and the API key.
3. Credentials are stored in the **Keychain** and are restored automatically when the app restarts.

## Development

```bash
# Swift Package Manager
swift build --package-path OutlineCore
swift test --package-path OutlineCore
```

## Contributing

Issues and pull requests are welcome. If you are planning a larger change, please open an issue first to discuss it.

## License

Licensed under the [Apache License 2.0](LICENSE).

This project is not affiliated with or endorsed by General Outline, Inc. Outline is a trademark of General Outline, Inc.

