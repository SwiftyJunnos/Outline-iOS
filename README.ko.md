# Outline iOS

영문 README는 [README.md](README.md)에서 볼 수 있습니다.

Outline 서버를 위한 비공식 iOS 클라이언트입니다. Outline에 저장된 문서를 iPhone과 iPad에서 읽을 수 있습니다.

Outline: <https://www.getoutline.com>

## 스크린샷

| 연결 화면 | 문서 목록 | 문서 읽기 |
| --- | --- | --- |
| ![연결 화면](Screenshots/connection.png) | ![문서 목록](Screenshots/documents.png) | ![문서 읽기](Screenshots/document.png) |

스크린샷은 추후 실제 기기 캡처로 교체하세요.

## 요구사항

- iOS 17.0 이상
- Outline 서버 (셀프 호스팅 또는 Outline Cloud)

## 빌드

1. Xcode로 `OutlineIOS.xcodeproj`를 엽니다.
2. 원하는 시뮬레이터 또는 기기를 선택합니다.
3. `Cmd + R`로 빌드·실행합니다.

## Outline 서버 연결

첫 실행 시 Outline 서버 URL과 API 키를 입력합니다.

1. Outline 서버 설정 → **API Keys**에서 읽어오기 전용 API 키를 생성합니다.
2. iOS 앱에서 서버 URL(예: `https://outline.example.com`)과 API 키를 입력합니다.
3. 자격 증명은 **Keychain**에 저장되며, 이후 앱 재실행 시 자동으로 복원됩니다.

## 개발

```bash
# Swift Package Manager
swift build --package-path OutlineCore
swift test --package-path OutlineCore
```

## 기여

이슈와 PR은 언제나 환영합니다. 큰 변경을 준비 중이라면 먼저 이슈를 열어 논의해주세요.

## 라이선스

[Apache License 2.0](LICENSE)에 따라 배포됩니다.

이 프로젝트는 General Outline, Inc.와 제휴하거나 보증받지 않은 비공식 프로젝트입니다. Outline은 General Outline, Inc.의 상표입니다.
