# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-05-19 (fork: hvkeyn)

### Added
- Large mod upload pipeline: `%LOCALAPPDATA%` staging, robocopy, path validation, preview re-encoding.
- Workshop upload progress dialog (log, progress bar, Copy log, Open in Steam).
- `ugc_item_registry` — per-app item IDs and tombstone list for deleted items.
- `workshop_scope_label` — shows which game Workshop items belong to.

### Changed
- Workshop dropdown clears and filters by current AppID when switching games.
- Drafts store `app_id`; only drafts for the selected game are merged on refresh.
- Main screen layout: smaller header, flexible columns, compact log area.

### Fixed
- Upload blocked while UGC query handle was active.
- Deleted Workshop items reappearing from drafts/registry.
- Steam overlay `overlay_toggled` signal missing (UI freeze).
- Accidental Shift+Submit metadata-only uploads removed; content folder required.

## [1.1.0] - 2025-05-19 (fork: hvkeyn)

### Added
- Full Steam library picker with search (all owned games from local Steam config).
- App name database from SteamCMD-AppID-List CSV (~165k entries) with Store API fallback.
- `start.ps1` launcher for Godot 4.6.2 or exported build.
- Folder picker dialog with pasteable full path and embedded browse.
- Remove files/folders from upload list (button + Delete key).
- Delete Workshop UGC items from the main screen.
- Responsive main window layout (PanelContainer, min window size 900×600).

### Changed
- Upgraded project target to **Godot 4.6.2**.
- Renamed autoload `Logger` → `AppLogger` (Godot 4.6 built-in conflict).
- Replaced hardcoded game dropdown with scrollable library list.

### Fixed
- `MasterList.get_name()` shadowing `Object.get_name()` breaking library scan.
- Log panel and controls not stretching on window resize.
- Workshop item dropdown crash when zero items returned.
- Per-app Steam re-initialization when switching games.

## [1.0.1] - 2025-05-18

### Added
- Added a "Formatting Help" button to the Description editor.
- Links in the Description editor can now be clicked.

### Changed
- Error codes in the log are now more readable

### Fixed
- Fixed an issue where the description wasn't being uploaded when submitting.
- Fixed an issue where the "Quit" and "Clear User Preferences" menu options would do nothing when clicked.
- Fixed an issue where the "Back" button would do nothing when clicked.

### Removed
- Hid the "UGC Item Type" dropdown since it isn't useful for most games, may re-enable under an "Advanced Options" in the future.


## [1.0.0] - 2025-05-11

Initial release.

### Added
- Added ability to create UGC items for listed games.
- Added ability to retrieve current user's UGC items for listed games.
- Added ability to edit and upload workshop metadata for UGC.
- Added ability to upload preview thumbnails for UGC (with support for static and animated images).
- Added ability to upload content for UGC from a selected folder.
- Added ability to exclude certain files from a UGC upload.
- Added ability to exclude files automatically via a .steamignore file.

