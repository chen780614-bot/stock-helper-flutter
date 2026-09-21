# stock_helper（股市助手）

## 版本

**1.0.2+3 穩定版** — 廣告暫改佔位、先確保可開啟

- 本版不呼叫 `MobileAds.initialize`，底部僅顯示虛線「廣告刊登位置」佔位，不建立 BannerAd / AdWidget。
- Release 關閉 R8 minify / shrinkResources，並以不加 `--obfuscate` 方式建置，優先保證可啟動。
- `google_mobile_ads` 依賴與 Manifest `APPLICATION_ID` 保留，之後可再啟用真實廣告。

## Getting Started

This project is a starting point for a Flutter application.

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.