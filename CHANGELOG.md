# Changelog

All notable changes to the `discourse-video-stream` plugin will be documented in this file.

## [Unreleased]

### Changed
- **Clean Video Embed BBCode**: Removed `provider` attribute from generated composer BBCode (`[video-stream id="..."]`). The video player automatically identifies the appropriate streaming service and falls back seamlessly, keeping the BBCode clean, user-friendly, and infrastructure-agnostic.

### Added
- **Dual-Provider Simultaneous Playback**: Supported simultaneous playback of videos hosted on both Cloudflare Stream and Bunny.net Stream regardless of which provider is currently active in site settings.
- **Automatic Fallback Resolution**: Shaka Player dynamically attempts candidate manifest sources across configured services and automatically aligns poster thumbnails with the working stream.
- **Bunny.net Stream Integration**: Added full support for Bunny.net Stream alongside Cloudflare Stream, selectable via the `video_stream_provider` setting with conditional admin UI visibility.
- **Configurable Max Duration**: Added `video_stream_max_duration` setting in the admin settings panel to customize maximum video duration limits (replacing the hardcoded 300-second limit).
- **Original File Name Option**: Added `video_stream_keep_original_name` setting (default `false`) to optionally preserve original video file names on Cloudflare and Bunny.

### Fixed
- **Bunny Stream TUS Resumable Upload**: Implemented pre-signed client credentials handshake via `/video-stream/prepare-upload.json` supplying `AuthorizationSignature`, `AuthorizationExpire`, `LibraryId`, and `VideoId` headers directly to `tus-js-client`, eliminating 400/404 errors and 0-byte video entries.
