# Discourse Video Stream

Discourse Video Stream adds a Cloudflare Stream and Bunny.net Stream-powered workflow for uploading and embedding long‑form video in the composer. Editors can upload large files directly from the composer toolbar and the plugin uses a custom BBCode syntax with Shaka Player for adaptive streaming playback.

## Features

- Optional composer toolbar button gated by the `video_stream_enabled` site setting
- Dropdown to choose between **Cloudflare Stream** and **Bunny.net Stream**
- Direct-upload modal with client-side validation for file size, extension, and optional original file name preservation
- Resumable uploads powered by vendored `tus-js-client`
- Secure server endpoints that proxy short‑lived upload URLs and authorization signatures
- Custom BBCode syntax `[video-stream id="..."]` for embedding videos
- Adaptive bitrate streaming using vendored Shaka Player with DASH/HLS manifests

## Setup

1. Install the plugin (add it to your `app.yml` or check it out into `plugins/`).
2. Enable the **Video streaming** category of site settings.
3. Select your streaming provider (`video_stream_provider`):
   - **Cloudflare**:
     - `video_stream_account_id`: Cloudflare account identifier
     - `video_stream_api_token`: API token with Stream permissions
     - `video_stream_customer_subdomain`: Playback domain (e.g. `customer-xxxxx.cloudflarestream.com`)
   - **Bunny**:
     - `video_stream_bunny_library_id`: Bunny.net Stream Video Library ID
     - `video_stream_bunny_api_key`: Bunny.net Stream API Key / AccessKey
     - `video_stream_bunny_hostname`: Bunny.net Pull Zone CDN hostname (e.g. `vz-xxxxxx.b-cdn.net`)
4. Adjust common settings as needed (allowed extensions, max file size in MB, max duration in seconds, keep original file name, native upload interception threshold, and live stream support).
5. Grant users appropriate upload permissions (`can_upload_external?` governs access to the endpoint).

Once configured:
- **Automatic interception**: Video files uploaded via drag & drop or the native upload button that exceed the configured size threshold will automatically be uploaded to the configured video streaming service
- **Manual upload**: Users can access the video upload option from the composer toolbar popup menu (three dots) for explicit uploads
- Uploaded videos are inserted as BBCode `[video-stream id="video_id"]` which renders as an adaptive streaming video player using Shaka Player

## Development

- JavaScript linting: `bin/lint plugins/discourse-video-stream`
- Ruby tests: `bin/rspec plugins/discourse-video-stream/spec`
- QUnit tests (if added): `bin/rake qunit:test FILTER='Video Stream'`

## Testing Notes

The server specs mock the Cloudflare API, so no external credentials are needed. The modal relies on the Discourse toast service; for manual testing you can run `bin/ember-cli` and visit `/latest` with video streaming enabled.
