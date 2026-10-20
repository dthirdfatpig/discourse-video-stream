import { withPluginApi } from "discourse/lib/plugin-api";
import { UploadPreProcessorPlugin } from "discourse/lib/uppy-plugin-base";
import VideoUploadModal from "../discourse/components/modal/video-upload-modal";

const BYTES_IN_MEGABYTE = 1_000_000;

/**
 * Check if a file should be intercepted and uploaded to Cloudflare Stream or Bunny.net Stream
 * @param {File} file
 * @param {object} siteSettings
 * @returns {boolean}
 */
function shouldInterceptUpload(file, siteSettings) {
  if (!siteSettings.video_stream_enabled) {
    return false;
  }

  if (!siteSettings.video_stream_intercept_native_uploads) {
    return false;
  }

  const provider = siteSettings.video_stream_provider || "cloudflare";
  if (provider === "bunny") {
    if (
      !siteSettings.video_stream_bunny_library_id ||
      !siteSettings.video_stream_bunny_hostname
    ) {
      return false;
    }
  } else {
    if (!siteSettings.video_stream_customer_subdomain) {
      return false;
    }
  }

  const thresholdMb =
    Number(siteSettings.video_stream_intercept_threshold_mb) || 0;
  const thresholdBytes = thresholdMb * BYTES_IN_MEGABYTE;

  return (file.size || 0) >= thresholdBytes;
}

/**
 * Get allowed video extensions from site settings
 * @param {object} siteSettings
 * @returns {string[]}
 */
function getAllowedExtensions(siteSettings) {
  return (
    siteSettings.video_stream_allowed_extensions
      ?.split(",")
      .map((ext) => ext.trim().toLowerCase())
      .filter(Boolean) ?? []
  );
}

/**
 * Check if a file matches allowed video extensions
 * @param {object} file
 * @param {object} siteSettings
 * @returns {boolean}
 */
function isMatchingVideo(file, siteSettings) {
  const extensions = getAllowedExtensions(siteSettings);
  if (!extensions.length) {
    return false;
  }
  const name = file.name || "";
  const match = name.match(/\.([a-zA-Z0-9]+)$/);
  if (!match) {
    return false;
  }
  return extensions.includes(match[1].toLowerCase());
}

/**
 * Preprocessor that intercepts video uploads meeting or exceeding the threshold
 * and redirects them to the video stream modal, while letting smaller videos
 * pass through to Discourse's native upload pipeline without hanging.
 */
class VideoStreamUploadPreProcessor extends UploadPreProcessorPlugin {
  static pluginId = "video-stream-upload-preprocessor";

  constructor(uppy, opts) {
    super(uppy, opts);
    this.composerModel = opts.composerModel;
    this.siteSettings = opts.siteSettings;
    this.modal = opts.modal;
    this.appEvents = opts.appEvents;
    this._processFiles = this._processFiles.bind(this);
  }

  install() {
    this._install(this._processFiles);
  }

  uninstall() {
    this._uninstall(this._processFiles);
  }

  _processFiles(fileIds) {
    const promises = (fileIds || []).map((fileId) => {
      const file = this._getFile(fileId);
      if (!file) {
        return Promise.resolve();
      }

      const fileObj = file.data || file;
      const isVideo = isMatchingVideo(file, this.siteSettings);
      const shouldIntercept =
        isVideo && shouldInterceptUpload(fileObj, this.siteSettings);

      if (shouldIntercept) {
        this.modal.show(VideoUploadModal, {
          model: {
            toolbarEvent: {
              addText: (text) => {
                const reply = this.composerModel?.reply || "";
                this.composerModel?.set?.(
                  "reply",
                  reply ? `${reply}\n\n${text}` : text
                );
              },
            },
            preselectedFile: fileObj,
          },
        });

        this._emitComplete(file, true);
        this.appEvents?.trigger?.("composer:cancel-upload", { fileId });
        return Promise.resolve();
      }

      // Allow file to continue through normal upload pipeline
      return this._emitComplete(file, true);
    });

    return Promise.all(promises);
  }
}

function initializeVideoUploadHandler(api) {
  const siteSettings = api.container.lookup("service:site-settings");
  const modal = api.container.lookup("service:modal");
  const appEvents = api.container.lookup("service:app-events");

  if (api.addComposerUploadPreProcessor) {
    api.addComposerUploadPreProcessor(
      VideoStreamUploadPreProcessor,
      ({ composerModel }) => {
        return {
          composerModel,
          siteSettings,
          modal,
          appEvents,
        };
      }
    );
  }
}

export default {
  name: "video-stream-upload-handler",
  initialize() {
    withPluginApi(initializeVideoUploadHandler);
  },
};
