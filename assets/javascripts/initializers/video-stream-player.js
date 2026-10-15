import loadScript from "discourse/lib/load-script";
import { withPluginApi } from "discourse/lib/plugin-api";

/**
 * Initialize Shaka Player for a video element
 * @param {HTMLElement} container - The video container element
 * @param {string} videoId
 * @param {string} customerSubdomain
 * @param {string} [provider]
 */
async function initializeShakaPlayer(
  container,
  videoId,
  customerSubdomain,
  provider = "cloudflare"
) {
  try {
    // Load Shaka Player UI library (includes base player + UI) and CSS from vendored assets
    await Promise.all([
      loadScript(
        "/plugins/discourse-video-stream/javascripts/shaka-player.ui.js"
      ),
      loadScript(
        "/plugins/discourse-video-stream/stylesheets/shaka-player.ui.css",
        { css: true }
      ),
    ]);

    // Check if browser is supported
    if (!window.shaka?.Player?.isBrowserSupported()) {
      // eslint-disable-next-line no-console
      console.error("Shaka Player: Browser not supported");
      return;
    }

    const videoElement = container.querySelector("video");
    if (!videoElement) {
      return;
    }

    // Create player instance and attach to video element
    const player = new window.shaka.Player();
    await player.attach(videoElement);

    // Create UI instance with the video element and container
    const ui = new window.shaka.ui.Overlay(player, container, videoElement);

    // Configure UI controls to match Shaka Player demo layout
    // This follows the same pattern as https://shaka-player-demo.appspot.com
    const config = {
      addBigPlayButton: true,
      addSeekBar: true,
      // Control bar layout matching the demo
      controlPanelElements: [
        "play_pause",
        "mute",
        "volume",
        "time_and_duration",
        "spacer",
        "overflow_menu",
        "fullscreen",
      ],
      // Overflow menu with quality and playback rate
      overflowMenuButtons: [
        "captions",
        "quality", // Resolution selection
        "language",
        "playback_rate", // Playback speed
        "picture_in_picture",
        "cast",
      ],
      // Enable keyboard shortcuts (space = play/pause, arrows = seek, etc.)
      enableKeyboardPlaybackControls: true,
    };

    ui.configure(config);

    // Determine manifest URIs based on provider
    let primaryManifestUri;
    let fallbackManifestUri;

    if (provider === "bunny") {
      primaryManifestUri = `https://${customerSubdomain}/${videoId}/playlist.m3u8`;
    } else {
      primaryManifestUri = `https://${customerSubdomain}/${videoId}/manifest/video.mpd`;
      fallbackManifestUri = `https://${customerSubdomain}/${videoId}/manifest/video.m3u8`;
    }

    try {
      await player.load(primaryManifestUri);
    } catch (primaryError) {
      if (fallbackManifestUri) {
        // eslint-disable-next-line no-console
        console.warn("Primary manifest failed, trying fallback:", primaryError);
        try {
          await player.load(fallbackManifestUri);
        } catch (fallbackError) {
          // eslint-disable-next-line no-console
          console.error("Both primary and fallback manifests failed:", {
            primary: primaryError,
            fallback: fallbackError,
          });
          container.innerHTML = `
            <div style="display: flex; align-items: center; justify-content: center; min-height: 200px; padding: 2em; text-align: center; color: var(--primary-medium);">
              <div>
                <p>Failed to load video</p>
                <p style="font-size: 0.9em; margin-top: 0.5em;">Video ID: ${videoId}</p>
              </div>
            </div>
          `;
          return;
        }
      } else {
        // eslint-disable-next-line no-console
        console.error("Failed to load manifest:", primaryError);
        container.innerHTML = `
          <div style="display: flex; align-items: center; justify-content: center; min-height: 200px; padding: 2em; text-align: center; color: var(--primary-medium);">
            <div>
              <p>Failed to load video</p>
              <p style="font-size: 0.9em; margin-top: 0.5em;">Video ID: ${videoId}</p>
            </div>
          </div>
        `;
        return;
      }
    }

    // Store player and ui instances on container for cleanup
    container.shakaPlayer = player;
    container.shakaUI = ui;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error("Failed to initialize Shaka Player:", error);
    // Show generic error message
    if (container) {
      container.innerHTML = `
        <div style="display: flex; align-items: center; justify-content: center; min-height: 200px; padding: 2em; text-align: center; color: var(--primary-medium);">
          <div>
            <p>Failed to initialize video player</p>
            <p style="font-size: 0.9em; margin-top: 0.5em;">Please check the console for details</p>
          </div>
        </div>
      `;
    }
  }
}

/**
 * Initialize video stream players in cooked content
 * @param {object} api
 */
function initializeVideoStreamPlayer(api) {
  const siteSettings = api.container.lookup("service:site-settings");

  api.decorateCookedElement(
    (element) => {
      const containers = element.querySelectorAll(".video-stream-container");

      if (!containers.length) {
        return;
      }

      const provider = siteSettings.video_stream_provider || "cloudflare";
      const customerSubdomain =
        provider === "bunny"
          ? siteSettings.video_stream_bunny_hostname?.trim()
          : siteSettings.video_stream_customer_subdomain?.trim();

      if (!customerSubdomain) {
        // eslint-disable-next-line no-console
        console.error(
          "Video Stream: playback domain/hostname not configured in site settings"
        );
        return;
      }

      containers.forEach((container) => {
        // Skip if already initialized
        if (container.querySelector("video")) {
          return;
        }

        const videoId = container.dataset.videoId;

        if (!videoId) {
          return;
        }

        // Create video element (Shaka UI will manage controls)
        const video = document.createElement("video");
        video.className = "video-stream-player";
        video.poster =
          provider === "bunny"
            ? `https://${customerSubdomain}/${videoId}/thumbnail.jpg`
            : `https://${customerSubdomain}/${videoId}/thumbnails/thumbnail.jpg`;

        // Add video to container
        container.appendChild(video);

        // Initialize Shaka Player with UI
        initializeShakaPlayer(container, videoId, customerSubdomain, provider);
      });
    },
    {
      id: "video-stream-player",
      onlyStream: true,
    }
  );

  // Clean up players on element removal
  api.decorateCookedElement(
    (element) => {
      return () => {
        const containers = element.querySelectorAll(".video-stream-container");
        containers.forEach((container) => {
          if (container.shakaPlayer) {
            container.shakaPlayer.destroy();
          }
        });
      };
    },
    {
      id: "video-stream-player-cleanup",
      onlyStream: true,
    }
  );
}

export default {
  name: "video-stream-player",
  initialize() {
    withPluginApi(initializeVideoStreamPlayer);
  },
};
