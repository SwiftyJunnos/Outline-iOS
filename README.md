# Outline iOS

Read this in [한국어](README.ko.md).

An iOS client for Outline servers. Read documents stored in Outline on iPhone and iPad.

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

1. Open `OutlineIOS.xcodeproj` in Xcode.
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

Business Source License 1.1 — see the [LICENSE](LICENSE) file.

Outline is a trademark of General Outline, Inc.

