# WhatsApp Sticker Creator — Design

Date: 2026-08-13

## Purpose

A Flutter app (Android + iOS) for building WhatsApp sticker packs from two
sources: images picked directly from the device, and images pulled from a
TikTok/Instagram/Pinterest link (via OS share sheet or pasted URL). Packs are
organized, edited into WhatsApp's required format, and handed off to
WhatsApp's "Add to WhatsApp" flow.

## Scope (v1)

- Static stickers (WebP, ≤100KB) and animated stickers (animated WebP,
  ≤500KB), both sourced only from **direct** imports (gallery images for
  static, GIF files for animated). Video-file import for animated stickers
  is out of scope for v1 — see Processing pipeline for why.
- Link import (share sheet + paste URL) is **static-thumbnail-only**: these
  platforms don't expose stable media-download APIs, and scraping video off
  TikTok is fragile and ToS-grey. Link import fetches a preview image
  (`og:image` / oEmbed thumbnail) and feeds it into the same static pipeline
  as a direct image import. It never produces an animated sticker.
- Crop/resize only — no background removal.
- No emoji tagging per sticker (empty emoji list; WhatsApp still accepts
  this).
- Multiple named packs, each with a user-chosen tray icon.
- Local-only data — no accounts, no sync, no backend.

## Architecture

Layered: `UI → Bloc (events/states) → Repository → Data sources`, using
`flutter_bloc`.

**Repositories** (the seam Bloc tests mock against):
- `PackRepository` — CRUD over packs/stickers in Hive + the sticker image
  files on disk
- `ImportRepository` — direct picks (gallery/file), OS share-sheet intents,
  and paste-URL thumbnail scraping
- `StickerProcessor` — crop/resize/compress/encode pipeline
- `WhatsAppHandoff` — platform channel wrapping the Android ContentProvider
  intent / iOS pasteboard+URL-scheme handoff

## Data model

Stored in Hive (`@HiveType` objects, no SQL, no JSON manifest):

```
StickerPack { id, name, publisherName, trayIconPath, stickers: List<Sticker> }
Sticker { id, filePath, type: static | animated }
```

Image bytes live as files on disk (in the app's documents directory); Hive
stores only metadata and file paths, not blobs.

## Import flows

**Direct import:**
- `image_picker` for gallery multi-select (static images)
- A file picker for GIF/video (animated source)
- Selected files feed directly into the processing pipeline, then get
  assigned to a pack (existing or newly created)

**Link import** — two entry points, same downstream handling:
- **Share sheet:** `receive_sharing_intent` (Android intent-filters) delivers
  a shared URL when the user taps Share inside TikTok/Instagram/Pinterest
  and picks this app. **Android only for v1** — the iOS side additionally
  needs a Share Extension Xcode target (new target, App Groups capability,
  entitlements), which is inherently a GUI/interactive Xcode-project
  operation, not something safely scriptable. Paste URL (below) is a full
  substitute on iOS, so this was accepted as a documented v1 platform gap
  rather than risking automated `.pbxproj` surgery for one of two link-entry
  points. Can be added later by following `receive_sharing_intent`'s README
  to set up the Xcode target manually.
- **Paste URL:** a text field validates the URL's domain, then fetches the
  page and extracts `og:image` (falling back to platform oEmbed endpoints
  where available, e.g. TikTok's oEmbed `thumbnail_url`). Works on both
  platforms.
- Both paths yield a static thumbnail image only. The user previews it and
  confirms before it enters the same pipeline as a direct static import.

## Processing pipeline (`StickerProcessor`)

- **Static:** crop (`image_cropper`) → resize to 512×512 → encode WebP
  (`flutter_image_compress`, native lossy encoder with a `quality` knob) →
  iteratively lower quality until ≤100KB
- **Animated** (direct GIF import only): decode multi-frame GIF → resize
  each frame to fit 512×512 → cap frame count/duration to WhatsApp's
  animated sticker limits → encode animated WebP (pure-Dart `image` package,
  `WebPEncoder`, lossless-only — no quality knob) → iteratively reduce color
  count (quantization) and/or frame count until ≤500KB.
  (Note: `ffmpeg_kit_flutter`, the tool originally named here, was retired
  in Jan 2025 with binaries pulled from Maven/CocoaPods/npm — this pipeline
  avoids it entirely in favor of pure-Dart encoding, with no native binary
  dependency.)
- **Tray icon:** user crops a square image → resize to 96×96 → encode PNG
  (`image` package)

## Pack management

- `PackListBloc`: create/rename/delete packs, list them
- `PackDetailBloc` (per pack): grid of stickers, add (opens import flow),
  remove, set/edit tray icon
- Validation: "Add to WhatsApp" stays disabled until the pack has 3–30
  stickers (WhatsApp's hard limits)

## WhatsApp handoff

- **Android:** requires a `ContentProvider` implementing WhatsApp's exact
  contract (specific URIs/columns per their published sample app at
  github.com/WhatsApp/stickers) plus an intent
  (`com.whatsapp.intent.action.ENQUEUE_STICKER_PACK`) to trigger the add UI.
  At implementation time, first check for a maintained Flutter plugin that
  bundles this native contract (e.g. `whatsapp_stickers_handler`); fall back
  to hand-writing the Kotlin `ContentProvider` against WhatsApp's sample
  only if no current plugin fits. Either way it reads pack/sticker data from
  Hive + the sticker files.
- **iOS:** writes the pack data to `UIPasteboard` with WhatsApp's expected
  keys, then opens the `whatsapp://stickerPack` URL scheme — no native
  App Extension needed on either platform, just platform channels
- Both paths detect "WhatsApp not installed" and show a message instead of
  failing silently

## Error handling

- Link scrape fails (no `og:image` found, blocked, timeout) → inline error,
  offer retry or fall back to direct import
- Pipeline can't hit the size budget after max compression attempts →
  surface the failure with the reason (e.g. "image too complex to fit
  100KB")
- Pack validation errors (sticker count, missing tray icon) shown inline,
  not as blocking dialogs

## Testing

- Bloc unit tests (`bloc_test`) for `PackListBloc`/`PackDetailBloc` against
  mocked repositories
- Pure unit tests for `StickerProcessor`'s compression loop and resize math
  against sample fixture images
- The actual "Add to WhatsApp" handoff cannot be meaningfully automated (it
  needs a real device with WhatsApp installed) — manual verification step,
  not CI-covered
