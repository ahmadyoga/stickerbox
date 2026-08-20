# Stickerbox

A Flutter app for building WhatsApp sticker packs.

## Features

- Create and manage sticker packs, add stickers from the device gallery or the share sheet
- Import images from shared links (Pinterest, Instagram, TikTok — including short-link resolution and carousel posts)
- Crop and center-crop stickers before encoding (static and animated GIF)
- Export packs to WhatsApp via its sticker `ContentProvider` integration
- Local persistence with Hive; no backend

## Project layout

- `lib/blocs` — state management (pack list, pack detail, import, theme)
- `lib/screens`, `lib/widgets` — UI
- `lib/repositories`, `lib/models`, `lib/hive` — data layer

## Getting Started

```
flutter pub get
flutter run
```

Run tests with `flutter test`.
