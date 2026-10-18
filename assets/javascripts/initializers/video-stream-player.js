import loadScript from "discourse/lib/load-script";
import { withPluginApi } from "discourse/lib/plugin-api";

function cleanDomain(domain) {
  if (!domain) {
    return "";
  }
  return domain
    .trim()
    .replace(/^https?:\/\//i, "")
    .replace(/\/+$/, "");
}

/**
 * Safely render an error message in a video container without raw innerHTML interpolation
 * @param {HTMLElement} container
 * @param {string} message
 * @param {string} [videoId]
 */
function renderErrorMessage(container, message, videoId) {
  container.innerHTML = "";
  const wrapper = document.createElement("div");
  wrapper.style.cssText =
    "display: flex; align-items: center; justify-content: center; min-height: 200px; padding: 2em; text-align: center; color: var(--primary-medium);";
  const inner = document.createElement("div");
  const p1 = document.createElement("p");
  p1.textContent = message;
  inner.appendChild(p1);
  if (videoId) {
    const p2 = document.createElement("p");
    p2.style.cssText = "font-size: 0.9em; margin-top: 0.5em;";
    p2.textContent = `Video ID: ${videoId}`;
    inner.appendChild(p2);
  }
  wrapper.appendChild(inner);
  container.appendChild(wrapper);
}

/**
 * Build an ordered list of candidate playback sources for a video.
 * If provider is specified in data-provider, that provider is prioritized.
 * If not specified, standard UUIDs with hyphens prioritize Bunny, otherwise
 * the currently active panel provider is tried first, followed by the other.
 *
 * @param {string} videoId
 * @param {string} [explicitProvider]
 * @param {object} siteSettings
 * @returns {Array<{ provider: string, manifestUri: string, poster: string }>}
 */
function getPlaybackSources(videoId, explicitProvider, siteSettings) {
  const cloudflareDomain = cleanDomain(
    siteSettings.video_stream_customer_subdomain
  );
  const bunnyDomain = cleanDomain(siteSettings.video_stream_bunny_hostname);
  const defaultProvider = siteSettings.video_stream_provider || "cloudflare";

  const bunnySources = bunnyDomain
    ? [
        {
          provider: "bunny",
          manifestUri: `https://${bunnyDomain}/${videoId}/playlist.m3u8`,
          poster: `https://${bunnyDomain}/${videoId}/thumbnail.jpg`,
        },
      ]
    : [];

  const cloudflareSources = cloudflareDomain
    ? [
        {
          provider: "cloudflare",
          manifestUri: `https://${cloudflareDomain}/${videoId}/manifest/video.mpd`,
          poster: `https://${cloudflareDomain}/${videoId}/thumbnails/thumbnail.jpg`,
        },
        {
          provider: "cloudflare",
          manifestUri: `https://${cloudflareDomain}/${videoId}/manifest/video.m3u8`,
          poster: `https://${cloudflareDomain}/${videoId}/thumbnails/thumbnail.jpg`,
        },
      ]
    : [];

  let preferredProvider;
  if (explicitProvider === "bunny" || explicitProvider === "cloudflare") {
    preferredProvider = explicitProvider;
  } else if (videoId.includes("-")) {
    // Standard UUIDs with hyphens are characteristic of Bunny Stream GUIDs
    preferredProvider = "bunny";
  } else {
    preferredProvider = defaultProvider;
  }

  if (preferredProvider === "bunny") {
    return [...bunnySources, ...cloudflareSources];
  } else {
    return [...cloudflareSources, ...bunnySources];
  }
}

/**
 * Check if the player container or its contents are currently in fullscreen mode
 * @param {HTMLElement} container
 * @returns {boolean}
 */
function isFullscreenActive(container) {
  if (!container) {
    return false;
  }
  const fsElem =
    document.fullscreenElement ||
    document.webkitFullscreenElement ||
    document.mozFullScreenElement ||
    document.msFullscreenElement;
  if (!fsElem) {
    return false;
  }
  return (
    fsElem === container ||
    container.contains(fsElem) ||
    fsElem.contains(container)
  );
}

/**
 * Apply the selected aspect ratio sizing and object-fit to the container and video element.
 * Works seamlessly in normal post view and inside fullscreen mode across desktop and mobile.
 *
 * @param {HTMLVideoElement} videoElement
 * @param {HTMLElement} container
 * @param {string} mode - "fit", "16:9", "4:3", "cover", "fill", "21:9"
 */
function applyAspectRatio(videoElement, container, mode) {
  if (!container) {
    return;
  }
  const currentMode = mode || container.dataset.aspectRatio || "fit";
  container.dataset.aspectRatio = currentMode;

  if (!videoElement) {
    return;
  }

  const inFullscreen = isFullscreenActive(container);

  if (inFullscreen) {
    container.style.removeProperty("aspect-ratio");
  }

  switch (currentMode) {
    case "16:9": {
      if (inFullscreen) {
        videoElement.style.setProperty("object-fit", "fill", "important");
        videoElement.style.setProperty(
          "width",
          "min(100vw, calc(100vh * 16 / 9))",
          "important"
        );
        videoElement.style.setProperty(
          "height",
          "min(100vh, calc(100vw * 9 / 16))",
          "important"
        );
      } else {
        container.style.setProperty("aspect-ratio", "16 / 9", "important");
        videoElement.style.setProperty("object-fit", "fill", "important");
        videoElement.style.setProperty("width", "100%", "important");
        videoElement.style.setProperty("height", "100%", "important");
      }
      break;
    }
    case "4:3": {
      if (inFullscreen) {
        videoElement.style.setProperty("object-fit", "fill", "important");
        videoElement.style.setProperty(
          "width",
          "min(100vw, calc(100vh * 4 / 3))",
          "important"
        );
        videoElement.style.setProperty(
          "height",
          "min(100vh, calc(100vw * 3 / 4))",
          "important"
        );
      } else {
        container.style.setProperty("aspect-ratio", "4 / 3", "important");
        videoElement.style.setProperty("object-fit", "fill", "important");
        videoElement.style.setProperty("width", "100%", "important");
        videoElement.style.setProperty("height", "100%", "important");
      }
      break;
    }
    case "21:9": {
      if (inFullscreen) {
        videoElement.style.setProperty("object-fit", "fill", "important");
        videoElement.style.setProperty(
          "width",
          "min(100vw, calc(100vh * 21 / 9))",
          "important"
        );
        videoElement.style.setProperty(
          "height",
          "min(100vh, calc(100vw * 9 / 21))",
          "important"
        );
      } else {
        container.style.setProperty("aspect-ratio", "21 / 9", "important");
        videoElement.style.setProperty("object-fit", "fill", "important");
        videoElement.style.setProperty("width", "100%", "important");
        videoElement.style.setProperty("height", "100%", "important");
      }
      break;
    }
    case "cover": {
      // Zoom (Crop)
      if (!inFullscreen) {
        container.style.setProperty("aspect-ratio", "16 / 9", "important");
      }
      videoElement.style.setProperty("object-fit", "cover", "important");
      videoElement.style.setProperty("width", "100%", "important");
      videoElement.style.setProperty("height", "100%", "important");
      break;
    }
    case "fill": {
      // Stretch (Fill)
      if (!inFullscreen) {
        container.style.setProperty("aspect-ratio", "16 / 9", "important");
      }
      videoElement.style.setProperty("object-fit", "fill", "important");
      videoElement.style.setProperty("width", "100%", "important");
      videoElement.style.setProperty("height", "100%", "important");
      break;
    }
    case "fit":
    default: {
      // Fit (Auto)
      if (!inFullscreen) {
        container.style.setProperty("aspect-ratio", "16 / 9", "important");
      }
      videoElement.style.setProperty("object-fit", "contain", "important");
      videoElement.style.setProperty("width", "100%", "important");
      videoElement.style.setProperty("height", "100%", "important");
      break;
    }
  }

  videoElement.style.setProperty("max-width", "100%", "important");
  videoElement.style.setProperty("max-height", "100%", "important");
  videoElement.style.setProperty("display", "block", "important");
  videoElement.style.setProperty("margin", "auto", "important");
}

let customElementsRegistered = false;

function registerCustomElements() {
  if (customElementsRegistered || !window.shaka?.ui) {
    return;
  }
  customElementsRegistered = true;

  // Custom Aspect Ratio Settings Menu
  class AspectRatioSelection extends window.shaka.ui.SettingsMenu {
    constructor(parent, controls) {
      super(parent, controls, "aspect_ratio");

      this.button.classList.add("shaka-aspect-ratio-button");
      this.menu.classList.add("shaka-aspect-ratio-menu");

      this.button.setAttribute("aria-label", "Aspect Ratio");
      if (this.nameSpan) {
        this.nameSpan.textContent = "Aspect Ratio";
      }
      if (this.backSpan) {
        this.backSpan.textContent = "Aspect Ratio";
      }

      this.options = [
        { id: "fit", label: "Fit (Auto)" },
        { id: "16:9", label: "16:9" },
        { id: "4:3", label: "4:3" },
        { id: "cover", label: "Zoom (Crop)" },
        { id: "fill", label: "Stretch (Fill)" },
        { id: "21:9", label: "21:9" },
      ];

      const container = this.controls.getVideoContainer();
      const video = this.controls.getVideo();
      const currentMode = container?.dataset?.aspectRatio || "fit";
      const initialOption =
        this.options.find((opt) => opt.id === currentMode) || this.options[0];

      if (this.currentSelection) {
        this.currentSelection.textContent = initialOption.label;
      }
      this.button.setAttribute("shaka-status", initialOption.label);

      applyAspectRatio(video, container, currentMode);

      this.buildMenu(currentMode);
    }

    buildMenu(selectedId) {
      this.options.forEach((opt) => {
        const button = document.createElement("button");
        button.setAttribute("type", "button");

        const span = document.createElement("span");
        span.textContent = opt.label;
        button.appendChild(span);

        if (opt.id === selectedId) {
          button.setAttribute("aria-selected", "true");
          span.classList.add("shaka-chosen-item");
          const checkIcon = document.createElement("i");
          checkIcon.classList.add("material-icons-round", "shaka-chosen-item");
          checkIcon.textContent = "done";
          checkIcon.setAttribute("aria-hidden", "true");
          button.appendChild(checkIcon);
        }

        this.eventManager.listen(button, "click", () => {
          this.selectOption(opt);
        });

        this.menu.appendChild(button);
      });
    }

    selectOption(opt) {
      const container = this.controls.getVideoContainer();
      const video = this.controls.getVideo();
      applyAspectRatio(video, container, opt.id);

      const prevIcon = this.menu.querySelector(
        ".shaka-chosen-item.material-icons-round"
      );
      if (prevIcon) {
        const prevButton = prevIcon.parentElement;
        prevButton.removeAttribute("aria-selected");
        const prevSpan = prevButton.querySelector("span");
        if (prevSpan) {
          prevSpan.classList.remove("shaka-chosen-item");
        }
        prevIcon.remove();
      }

      const buttons = this.menu.querySelectorAll("button");
      buttons.forEach((btn) => {
        const span = btn.querySelector("span");
        if (span && span.textContent === opt.label) {
          btn.setAttribute("aria-selected", "true");
          span.classList.add("shaka-chosen-item");
          const checkIcon = document.createElement("i");
          checkIcon.classList.add("material-icons-round", "shaka-chosen-item");
          checkIcon.textContent = "done";
          checkIcon.setAttribute("aria-hidden", "true");
          btn.appendChild(checkIcon);
        }
      });

      if (this.currentSelection) {
        this.currentSelection.textContent = opt.label;
      }
      this.button.setAttribute("shaka-status", opt.label);
    }
  }

  class AspectRatioSelectionFactory {
    create(rootElement, controls) {
      return new AspectRatioSelection(rootElement, controls);
    }
  }

  window.shaka.ui.OverflowMenu.registerElement(
    "aspect_ratio",
    new AspectRatioSelectionFactory()
  );
  window.shaka.ui.Controls.registerElement(
    "aspect_ratio",
    new AspectRatioSelectionFactory()
  );
}

/**
 * Initialize Shaka Player for a video element
 * @param {HTMLElement} container - The video container element
 * @param {string} videoId
 * @param {Array<{ provider: string, manifestUri: string, poster: string }>} sources
 * @param {HTMLVideoElement} videoElement
 * @param {object} siteSettings
 */
async function initializeShakaPlayer(
  container,
  videoId,
  sources,
  videoElement,
  siteSettings
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

    if (!videoElement) {
      return;
    }

    // Register custom Aspect Ratio UI button
    registerCustomElements();

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
      // Prevent orientation lock crashes and unwanted auto-rotation on mobile (e.g., Android Firefox)
      forceLandscapeOnFullscreen: false,
      enableFullscreenOnRotation: false,
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
      // Overflow menu with quality, aspect ratio, and playback rate
      overflowMenuButtons: [
        "captions",
        "quality", // Resolution selection
        "aspect_ratio", // Aspect ratio changer
        "language",
        "playback_rate", // Playback speed
        "picture_in_picture",
        "cast",
      ],
      // Enable keyboard shortcuts (space = play/pause, arrows = seek, etc.)
      enableKeyboardPlaybackControls: true,
    };

    ui.configure(config);

    // Guard against mobile browsers (especially Firefox on Android) resetting video.currentTime to 0
    // or pausing playback when entering/exiting native fullscreen, and ensure aspect ratio persists.
    let lastPlaybackTime = 0;
    let wasPlayingBeforeFullscreen = false;
    let isFullscreenTransition = false;

    const onTimeUpdate = () => {
      if (videoElement.currentTime > 0.5) {
        lastPlaybackTime = videoElement.currentTime;
      }
    };

    const onPlay = () => {
      wasPlayingBeforeFullscreen = true;
    };

    const onPause = () => {
      if (!isFullscreenTransition) {
        wasPlayingBeforeFullscreen = false;
      }
    };

    const restorePlaybackState = () => {
      if (lastPlaybackTime > 0.5 && videoElement.currentTime < 0.5) {
        try {
          videoElement.currentTime = lastPlaybackTime;
        } catch (_) {}

        if (wasPlayingBeforeFullscreen && videoElement.paused) {
          videoElement.play().catch(() => {});
        }
      }
    };

    const handleFullscreenTransition = () => {
      restorePlaybackState();
      applyAspectRatio(
        videoElement,
        container,
        container.dataset.aspectRatio || "fit"
      );
    };

    const onFullscreenChange = () => {
      isFullscreenTransition = true;
      handleFullscreenTransition();
      setTimeout(handleFullscreenTransition, 100);
      setTimeout(handleFullscreenTransition, 250);
      setTimeout(handleFullscreenTransition, 500);
      setTimeout(() => {
        handleFullscreenTransition();
        isFullscreenTransition = false;
      }, 800);
    };

    const onWindowResize = () => {
      applyAspectRatio(
        videoElement,
        container,
        container.dataset.aspectRatio || "fit"
      );
    };

    videoElement.addEventListener("timeupdate", onTimeUpdate);
    videoElement.addEventListener("play", onPlay);
    videoElement.addEventListener("pause", onPause);

    document.addEventListener("fullscreenchange", onFullscreenChange);
    document.addEventListener("webkitfullscreenchange", onFullscreenChange);
    document.addEventListener("mozfullscreenchange", onFullscreenChange);
    window.addEventListener("resize", onWindowResize);
    window.addEventListener("orientationchange", onWindowResize);

    container._videoStreamCleanup = () => {
      videoElement.removeEventListener("timeupdate", onTimeUpdate);
      videoElement.removeEventListener("play", onPlay);
      videoElement.removeEventListener("pause", onPause);
      document.removeEventListener("fullscreenchange", onFullscreenChange);
      document.removeEventListener("webkitfullscreenchange", onFullscreenChange);
      document.removeEventListener("mozfullscreenchange", onFullscreenChange);
      window.removeEventListener("resize", onWindowResize);
      window.removeEventListener("orientationchange", onWindowResize);
    };

    // Try playback sources in order until one succeeds
    let successfulSource = null;
    let lastError = null;

    for (let i = 0; i < sources.length; i++) {
      const source = sources[i];
      try {
        if (i > 0) {
          await player.unload(false).catch(() => {});
        }
        await player.load(source.manifestUri);
        successfulSource = source;
        break;
      } catch (loadError) {
        lastError = loadError;
      }
    }

    if (!successfulSource) {
      // eslint-disable-next-line no-console
      console.error("All video manifest sources failed to load:", {
        videoId,
        lastError,
        sources,
      });
      renderErrorMessage(container, "Failed to load video", videoId);
      return;
    }

    // Set resolved provider
    container.dataset.resolvedProvider = successfulSource.provider;

    // Apply aspect ratio
    applyAspectRatio(
      videoElement,
      container,
      container.dataset.aspectRatio || "fit"
    );

    // Update poster to matching provider if different from initial
    if (
      videoElement &&
      successfulSource.poster &&
      videoElement.poster !== successfulSource.poster
    ) {
      videoElement.poster = successfulSource.poster;
    }

    // Store player and ui instances on container for cleanup
    container.shakaPlayer = player;
    container.shakaUI = ui;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error("Failed to initialize Shaka Player:", error);
    if (container) {
      renderErrorMessage(
        container,
        "Failed to initialize video player. Please check the console for details."
      );
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

      const cloudflareDomain = cleanDomain(
        siteSettings.video_stream_customer_subdomain
      );
      const bunnyDomain = cleanDomain(siteSettings.video_stream_bunny_hostname);

      if (!cloudflareDomain && !bunnyDomain) {
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

        const explicitProvider = container.dataset.provider?.toLowerCase();
        const sources = getPlaybackSources(
          videoId,
          explicitProvider,
          siteSettings
        );

        if (!sources.length) {
          renderErrorMessage(container, "Playback not configured", videoId);
          return;
        }

        // Create video element (Shaka UI will manage controls)
        const video = document.createElement("video");
        video.className = "video-stream-player";
        if (sources[0]?.poster) {
          video.poster = sources[0].poster;
        }

        // Add video to container
        container.appendChild(video);

        // Initialize Shaka Player with UI
        initializeShakaPlayer(container, videoId, sources, video, siteSettings);
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
          if (container._videoStreamCleanup) {
            container._videoStreamCleanup();
            container._videoStreamCleanup = null;
          }
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
