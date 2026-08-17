# Design Import: Visual Redesign + Feature Additions

Date: 2026-08-15

## Purpose

Implement a complete visual redesign of the app sourced from an external
Claude Design mockup (`claude.ai/design/p/fdc7432c-fd79-490f-a730-e9ff479012e8`,
file `Sticker Pack App.dc.html`), plus the interaction features that mockup
introduces beyond what v1 shipped with. The mockup is a fully-specified
interactive prototype — every screen, state, and copy string is already
decided there; this spec covers only how that maps onto this codebase's
existing Flutter/Bloc architecture.

The source mockup (design tokens, exact layout/copy for every screen and
state) is the visual reference for implementation and is not re-transcribed
here — implementers should read it directly via the `DesignSync` MCP tool
(`get_file` on the project above) rather than trust a paraphrase.

## Scope

**In scope:**
- Visual redesign of all three existing screens (Home/Pack List, Pack
  Detail, Import) to match the mockup's design language (colors, typography,
  card/button shapes, layout).
- Dark mode (manual toggle, persisted).
- Rename pack (UI didn't exist before; `PackListBloc`'s `PackRenamed` event
  did but was unused).
- WhatsApp confirm → success sheet flow, and a "WhatsApp isn't installed"
  dialog (replacing today's direct-call + SnackBar).
- A processing bottom sheet with live progress ("4 of 8"), replacing
  today's full-screen blocking spinner.
- Toast notifications (via restyled `SnackBar`).
- A new custom Flutter `CropScreen` for the tray-icon flow, replacing
  `image_cropper`'s native crop UI (which cannot be visually themed).

**Out of scope (unchanged from v1):**
- Everything the original spec already excluded: emoji tagging, background
  removal, video-file animated import, cloud sync/accounts.
- Renaming the Android/iOS package id or app-store-facing identity — only
  the visible in-app header text changes, from "Sticker Packs" to
  "Stickerbox".
- Accent color customization as a user-facing setting. The mockup's
  `accent` prop is a *design-tool* preview knob (lets the designer preview
  4 color options); it ships fixed to the mockup's default, `#F4623A`.
- Cropping stickers themselves (only the tray icon uses the new crop flow —
  stickers are auto-cropped/resized by `StickerProcessor` as before, no UI
  change there).

## App icon + logo mark

Two source images now provided (`assets/app-icon.png`, `assets/icon.png` —
same ghost/pocket mascot, matching the mockup's branding):
- `assets/app-icon.png` (opaque, gradient background, square): the platform
  launcher icon. Generated for Android/iOS via `flutter_launcher_icons` (dev
  dependency) rather than hand-placing per-density PNGs.
- `assets/icon.png` (transparent cutout): used as the illustration in the
  Home and Pack-Detail empty states, standing in for the mockup's hand-drawn
  CSS sticker/ghost animation (keyframe-animated shapes built from dozens of
  absolutely-positioned divs) — not worth reproducing pixel-for-pixel in
  Flutter when a real mascot asset already exists. Bundled as a normal
  Flutter asset, not app-icon generation.

## Architecture additions

### Dark mode
A `ThemeCubit` (flutter_bloc, matching the rest of the app), holding
`ThemeMode`. Persisted to a new one-key Hive box (`settings`, key
`isDark`) so it survives restarts. `MaterialApp` reads `theme`/`darkTheme`/
`themeMode` from it. Colors live in `lib/theme.dart`, mapping the mockup's
exact light/dark token values (`c_bg`/`c_surf`/`c_surf2`/`c_tx`/`c_mut`/
`c_line`/`c_acc`/`c_accSoft`) to a Flutter `ColorScheme`/`ThemeData` pair.
The toggle is manual only (a button in both Home's and Detail's header,
per the mockup) — no system-theme following, since the mockup's own
interaction model is an explicit toggle, not automatic.

### Custom crop screen
`image_cropper`'s crop UI is a native OS view (Android's uCrop, iOS's
TOCropViewController) and cannot be restyled to match the mockup's dark
themed crop screen. Replaced, for the tray-icon flow only, with:
- A well-maintained pure-Flutter crop package (a real Flutter widget, so
  it's themeable) handling the actual pan/zoom/crop-region math. Exact
  package choice is verified at implementation time (same "check what's
  current on pub.dev" approach used for other dependency choices in this
  project) rather than pinned here.
- Our own `CropScreen` widget wrapping it, matching the mockup's layout:
  dark full-screen, header (close/title/"1:1 · 96×96" label), image with
  grid overlay, small preview thumbnail, Cancel/"Use as tray icon" buttons.
- On confirm, the cropped square image is written to a temp file and
  passed to `PackDetailBloc`'s existing `TrayIconSet` event — `_onTrayIconSet`
  already calls `StickerProcessor.encodeTrayIcon` on whatever path it's
  given (fixed in the original build's Task 12), so no change needed there.

### Toast notifications
Reuses `ScaffoldMessenger`'s `SnackBar` (already used for errors elsewhere
in the app), restyled as a floating dark rounded pill per the mockup — no
new notification framework.

### Processing sheet with live progress
`ImportState`'s `ImportProcessing` gains optional `current`/`total` int
fields (null for single-item flows: GIF pick, link import). `ImportBloc`'s
static-image batch handler emits an updated `ImportProcessing(current,
total)` after each image finishes encoding, instead of awaiting the whole
batch silently. The Detail screen's processing sheet reads these fields to
show "N of M" and a progress bar; `ImportFailure` drives the sheet into its
failed state (message + Cancel/Try Again) instead of a `SnackBar`.

### ImportBloc lifetime change (the one real architectural change)
In the mockup, picking images closes the Import screen immediately and
shows the processing sheet — with live progress — back on the Detail
screen, rather than blocking on the Import screen with a spinner as today.
This requires `ImportBloc` to be provided at the `PackDetailScreen` level
(alongside its own `PackDetailBloc`) instead of being scoped only to the
pushed `ImportScreen` route as it is today, so the Detail screen can keep
listening to it after the Import route pops. `ImportScreen` itself pops
immediately once an import event is dispatched (rather than waiting for
`ImportReady`); the processing sheet on Detail is what shows progress and
failure from then on.

## Per-screen changes

**PackListScreen (Home):** custom header (large title "Stickerbox" +
subtitle + dark-mode toggle) replacing the `AppBar`. Redesigned pack cards
(tray thumbnail/placeholder, meta text, up to 4 mini sticker previews,
overflow menu). "Create Pack" becomes a bottom-pinned CTA opening a bottom
sheet (name + optional author, dispatches the existing `PackCreated`
event) instead of today's `AlertDialog`. Overflow menu (bottom sheet):
Rename (dispatches `PackListBloc`'s existing `PackRenamed` event) and
Delete (existing `PackDeleted` event).

**PackDetailScreen:** custom header (back, name, dark toggle, overflow
menu). Tray icon card with Change/Set-icon button routing into
`CropScreen`. Sticker count header ("N / 30") with "+ Add" (or "Pack full"
badge at 30). Redesigned sticker grid (rounded tiles, GIF badge, remove
button). Bottom CTA gains a real disabled state with helper text explaining
what's missing — derived from `pack.stickers.length` and
`pack.trayIconPath`, computed in the widget from data `PackDetailBloc`
already exposes, no new bloc state needed. Tapping "Add to WhatsApp" opens
a confirm sheet (pack summary) → on confirm, calls the existing
`WhatsAppHandoff` → success sheet, or (if not installed) a centered dialog
replacing today's SnackBar. Detail's own overflow menu (Rename/Delete)
needs its own path since Detail doesn't have `PackListBloc` in scope — two
new `PackDetailBloc` events (`PackRenameRequested`, `PackDeleteRequested`),
mirroring the existing `TrayIconSet` event's pattern of calling the
repository directly. On delete, the screen pops back to Home; Home's
`Navigator.push(...).then(...)` (new) re-dispatches
`PackListLoadRequested()` on return, so renamed/deleted/sticker-count
changes are reflected without a separate cross-bloc signal.

**ImportScreen:** pill-style segmented tabs replacing the `TabBar`.
Device tab: redesigned "Choose Images"/"Choose GIF" cards. Link tab:
redesigned field/Paste button/source chips (TikTok/Instagram/Pinterest,
decorative, matching the mockup — not functionally different from today)
and states (loading, found-preview, error). Error copy shows the actual
`LinkThumbnailException` message rather than the mockup's 3 hardcoded
canned variants, so UI text can't drift from what the code actually
reports. On dispatching any pick/import action, the screen pops
immediately (see ImportBloc lifetime change above) rather than waiting.

## Testing

Consistent with how this app has been tested throughout: bloc-level logic
gets `bloc_test` coverage — `ThemeCubit` (toggle + persistence),
`ImportProcessing`'s new progress fields and emission order, `PackDetailBloc`'s
new rename/delete events. Pure UI (redesigned screens, new sheets,
`CropScreen`) gets no automated tests, matching this project's existing
convention that screens aren't unit-tested — verified by running the app.
