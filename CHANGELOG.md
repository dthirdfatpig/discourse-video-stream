# Changelog

All notable changes to the `discourse-video-stream` plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.0.11] - 2026-10-18

### Added
- **Download Button in Overflow Menu**: Added a "Download" button to the player's 3-dot overflow menu (`file_download` icon), triggering direct MP4 video downloads for both Bunny.net Stream and Cloudflare Stream.
- **Aspect Ratio Selector in Overflow Menu**: Added an "Aspect Ratio" submenu to the 3-dot overflow menu allowing users to switch dynamically between Fit (Auto), 16:9 (Widescreen), 4:3 (Standard), Zoom (Crop), Stretch (Fill), and 21:9 (Cinema) in both post embed view and fullscreen mode.

---

## [0.0.10] - 2026-10-18

### Changed
- Reverted experimental in-memory provider caching in the video player per feedback, ensuring fresh and reliable manifest loading across sessions.

### Fixed
- **Fullscreen Video Sizing**: Fixed videos rendering as a small box at the top of the screen in fullscreen mode on high-resolution displays (e.g. 1440p) by overriding Discourse core's `.cooked video` `max-height: 500px` restriction with full viewport scaling (`100vw`/`100vh`) and centered `object-fit: contain`.
- **Android Firefox Fullscreen Reset**: Fixed video pausing and restarting from 0:00 when entering fullscreen on Android Firefox by disabling `forceLandscapeOnFullscreen` and `enableFullscreenOnRotation` (preventing device orientation lock crashes).
- **Playback Timeline Restoration**: Added automatic playback state and timestamp preservation during fullscreen transitions to recover smoothly if a mobile browser drops or reloads the media pipeline.

---

## [0.0.9] - 2026-10-17

### Added
- **Security & Secret Masking**: Added `secret: true` to `video_stream_api_token` and `video_stream_bunny_api_key` in site settings to mask sensitive credentials in the Discourse admin UI and protect staff action logs.
- **Worker Hang & Latency Protection**: Configured connection (`5s`) and read (`15s`) timeouts across all Faraday HTTP requests (Cloudflare & Bunny) to prevent Puma/Unicorn worker thread exhaustion during external API slowdowns.
- **Input Sanitization**: Sanitized video titles and live stream names against ASCII control characters and enforced a 255-character length limit.
- **Error Handling Hardening**: Protected API response parsing against HTML/non-JSON CDN error pages to prevent unhandled parser exceptions.
- **DOM Injection Safety**: Switched player error container rendering from `innerHTML` template strings to safe DOM manipulation (`textContent`).

---

## [0.0.8] - 2026-10-17

### Changed
- **Clean Video Embed BBCode**: Removed the `provider` attribute from generated composer BBCode (`[video-stream id="..."][/video-stream]`), keeping post markup clean, concise, and infrastructure-agnostic while preserving automatic provider detection.

---

## [0.0.7] - 2026-10-16

### Added
- **Dual-Provider Simultaneous Playback**: Supported simultaneous playback of videos hosted on both Cloudflare Stream and Bunny.net Stream regardless of which provider is currently active in the site settings.
- **Multi-Source Manifest Fallback**: Shaka Player dynamically attempts candidate manifest sources across configured services and automatically updates poster thumbnails to match the working stream.

---

## [0.0.6] - 2026-10-16

### Added
- Pre-signed client handshake via `/video-stream/prepare-upload.json` supplying `AuthorizationSignature`, `AuthorizationExpire`, `LibraryId`, and `VideoId` headers to `tus-js-client`.

### Fixed
- **Bunny Direct TUS Upload**: Fixed 400/404 errors and 0-byte video entries on Bunny.net by establishing proper pre-signed authentication headers directly on client-side uploads.

---

## [0.0.5] - 2026-10-15

### Added
- **Bunny.net Stream Integration**: Added full support for Bunny.net Stream alongside Cloudflare Stream.
- **Provider Selector**: Added `video_stream_provider` setting with conditional admin UI visibility for provider-specific credentials (Cloudflare Account ID / API Token vs. Bunny Library ID / Hostname / API Key).
- Backend services and routes supporting Bunny video upload and live stream creation.

---

## [0.0.4] - 2026-10-14

### Changed
- Moved the "Keep original file name" configuration exclusively to the Discourse Admin plugin settings panel (`video_stream_keep_original_name`).

### Removed
- Removed the duplicate "Keep original file name" checkbox from the composer video upload modal to simplify the upload experience.

---

## [0.0.3] - 2026-10-14

### Added
- Added an optional "Keep original file name" checkbox in the video upload modal (default off) allowing users to preserve original filenames on Cloudflare Stream.

---

## [0.0.2] - 2026-10-13

### Added
- Added `video_stream_max_duration` setting in Discourse Admin to customize maximum video duration limits (replacing the hardcoded 300-second limit).

---

## [0.0.1] - 2026-10-12

### Added
- Initial release of `discourse-video-stream`.
- Cloudflare Stream integration with resumable client-side video uploads using `tus-js-client`.
- Custom BBCode format `[video-stream id="..."][/video-stream]`.
- Shaka Player UI integration with quality resolution switching and playback speed controls.
- Automatic interception of native video uploads exceeding configured size thresholds.
- Live stream creation modal with RTMPS server credentials and stream key generation.
