import { withPluginApi } from "discourse/lib/plugin-api";
import VideoUploadModal from "../discourse/components/modal/video-upload-modal";

const BYTES_IN_MEGABYTE = 1_000_000;

/**
 * Check if a file should be intercepted and uploaded to Cloudflare Stream
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

  const thresholdBytes =
    siteSettings.video_stream_intercept_threshold_mb * BYTES_IN_MEGABYTE;

  return file.size >= thresholdBytes;
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
 * Handle video upload by intercepting and redirecting to Cloudflare Stream modal
 * @param {object} api
 */
function initializeVideoUploadHandler(api) {
  const siteSettings = api.container.lookup("service:site-settings");
  const modal = api.container.lookup("service:modal");

  // Get allowed video extensions
  const extensions = getAllowedExtensions(siteSettings);

  if (!extensions.length) {
    return;
  }

  // Register upload handler for video files
  api.addComposerUploadHandler(extensions, (files, composerUploadInstance) => {
    // Filter files that should be intercepted
    const filesToIntercept = files.filter((file) =>
      shouldInterceptUpload(file, siteSettings)
    );

    if (filesToIntercept.length === 0) {
      // Let Discourse handle these uploads normally
      return true;
    }

    // Show modal for each intercepted file
    filesToIntercept.forEach((file) => {
      modal.show(VideoUploadModal, {
        model: {
          toolbarEvent: {
            addText: (text) => {
              const reply = composerUploadInstance.composerModel.reply || "";
              composerUploadInstance.composerModel.set("reply", reply + text);
            },
          },
          preselectedFile: file,
        },
      });
    });

    // Return false to prevent normal upload processing for intercepted files
    return false;
  });
}

export default {
  name: "video-stream-upload-handler",
  initialize() {
    withPluginApi(initializeVideoUploadHandler);
  },
};
