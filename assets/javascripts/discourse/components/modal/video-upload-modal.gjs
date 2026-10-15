import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import loadScript from "discourse/lib/load-script";
import { i18n } from "discourse-i18n";

const BYTES_IN_MEGABYTE = 1_000_000;
const DEFAULT_TUS_CHUNK_SIZE = 52_428_800; // 50 MB, divisible by 256 KiB
const TUS_ENDPOINT = "/video-stream/upload-url.json";

/**
 * @component video-upload-modal
 * @param {{ toolbarEvent?: { addText?: (value: string) => void }, preselectedFile?: File }} this.args.model
 */
export default class VideoUploadModal extends Component {
  @service siteSettings;
  @service toasts;

  /**
   * @type {boolean}
   */
  @tracked isUploading = false;

  /**
   * @type {number}
   */
  @tracked uploadProgress = 0;

  /**
   * @type {boolean}
   */
  @tracked
  keepOriginalName = Boolean(this.siteSettings.video_stream_keep_original_name);

  activeUpload = null;
  latestStreamMediaId = null;

  constructor() {
    super(...arguments);

    // If a preselected file was provided, start uploading it immediately
    const preselectedFile = this.args.model?.preselectedFile;
    if (preselectedFile) {
      this.uploadFile(preselectedFile);
    }
  }

  willDestroy() {
    super.willDestroy?.();
    this.resetUploaderState({ abortUpload: true });
  }

  /**
   * @returns {string|undefined}
   */
  get customerSubdomain() {
    return this.siteSettings.video_stream_customer_subdomain?.trim();
  }

  /**
   * @returns {string[]}
   */
  get allowedExtensions() {
    return (
      this.siteSettings.video_stream_allowed_extensions
        ?.split(",")
        .map((ext) => ext.trim().toLowerCase())
        .filter(Boolean) ?? []
    );
  }

  /**
   * @returns {number}
   */
  get maxFileSizeBytes() {
    return (
      Number(this.siteSettings.video_stream_max_file_size || 0) *
      BYTES_IN_MEGABYTE
    );
  }

  /**
   * @returns {string[]}
   */
  get uppyAllowedFileTypes() {
    if (!this.allowedExtensions.length) {
      return ["video/*"];
    }

    return this.allowedExtensions.map((ext) => `.${ext}`);
  }

  get fileInputAccept() {
    return this.uppyAllowedFileTypes.join(",");
  }

  /**
   * @returns {number}
   */
  get chunkSize() {
    return DEFAULT_TUS_CHUNK_SIZE;
  }

  get progressStyle() {
    return htmlSafe(`width: ${this.uploadProgress}%`);
  }

  /**
   * @param {HTMLInputElement} target
   */
  resetInputValue(target) {
    if (target) {
      target.value = "";
    }
  }

  /**
   * @param {string} key
   * @param {Record<string, unknown>} interpolations
   */
  showToast(key, interpolations = {}) {
    this.toasts.error({
      duration: "short",
      data: { message: i18n(key, interpolations) },
    });
  }

  /**
   * @param {File} file
   * @returns {boolean}
   */
  validateFilePresence(file) {
    if (file) {
      return true;
    }

    this.showToast("video_stream.upload_failed");
    return false;
  }

  /**
   * @returns {boolean}
   */
  validateConfiguration() {
    if (this.customerSubdomain) {
      return true;
    }

    this.showToast("video_stream.subdomain_missing");
    return false;
  }

  /**
   * @param {File} file
   * @returns {boolean}
   */
  validateExtension(file) {
    if (!this.allowedExtensions.length) {
      return true;
    }

    const extension = file.name.split(".").pop()?.toLowerCase();
    if (extension && this.allowedExtensions.includes(extension)) {
      return true;
    }

    this.showToast("video_stream.invalid_extension", {
      extensions: this.allowedExtensions.join(", "),
    });
    return false;
  }

  /**
   * @param {File} file
   * @returns {boolean}
   */
  validateFileSize(file) {
    if (!this.maxFileSizeBytes) {
      return true;
    }

    if (file.size <= this.maxFileSizeBytes) {
      return true;
    }

    this.showToast("video_stream.file_too_large", {
      max_size_mb: this.siteSettings.video_stream_max_file_size,
    });
    return false;
  }

  /**
   * @param {{ uid: string }} result
   */
  insertEmbed(result) {
    const toolbarEvent = this.args.model?.toolbarEvent;

    if (!toolbarEvent?.addText) {
      this.showToast("video_stream.missing_toolbar_event");
      return;
    }

    const uid = result.uid;
    const bbcode = `\n\n[video-stream id="${uid}"]\n[/video-stream]\n\n`;

    toolbarEvent.addText(bbcode);
    this.args.closeModal?.();
  }

  async _startTusUpload(file) {
    this.resetUploaderState({ abortUpload: true });
    this.isUploading = true;
    this.uploadProgress = 0;

    const TusUpload = await this._getTusUploadClass();
    if (!TusUpload) {
      throw new Error("tus-js-client global is unavailable");
    }

    const upload = new TusUpload(file, {
      endpoint: TUS_ENDPOINT,
      chunkSize: this.chunkSize,
      retryDelays: [0, 2000, 5000, 10000],
      removeFingerprintOnSuccess: true,
      metadata: this._tusMetadata(file),
      onBeforeRequest: (req) => {
        const url = req.getURL();
        // Only add CSRF token for requests to Discourse backend (relative URLs)
        // Don't add it for Cloudflare Stream requests (absolute URLs)
        if (url && url.startsWith("/")) {
          const token = this._csrfToken();
          if (token) {
            req.setHeader("X-CSRF-Token", token);
          }
        }
        return Promise.resolve();
      },
      onAfterResponse: (req, res) => {
        if (req?.getMethod?.() === "POST") {
          this.latestStreamMediaId =
            res?.getHeader?.("stream-media-id") || null;
        }

        return Promise.resolve();
      },
      onProgress: (bytesUploaded, bytesTotal) => {
        if (bytesTotal) {
          this.uploadProgress = Math.round((bytesUploaded / bytesTotal) * 100);
        }
      },
      onSuccess: () => {
        this._handleUploadSuccess({ uploadURL: upload.url });
      },
      onError: (error) => {
        this._handleUploadFailure(error);
      },
    });

    this.activeUpload = upload;

    upload
      .findPreviousUploads()
      .then((previousUploads) => {
        if (previousUploads?.length) {
          upload.resumeFromPreviousUpload(previousUploads[0]);
        }

        upload.start();
      })
      .catch((error) => {
        this._handleUploadFailure(error);
      });
  }

  _handleUploadSuccess(response) {
    const uid =
      this.latestStreamMediaId || this._extractUidFromUrl(response?.uploadURL);

    if (!uid) {
      this.showToast("video_stream.upload_failed");
      this.resetUploaderState();
      return;
    }

    this.insertEmbed({ uid });
    this.resetUploaderState();
  }

  _handleUploadFailure(error) {
    if (error) {
      // eslint-disable-next-line no-console
      console.error("Video upload failed", error);
    }

    this.showToast("video_stream.upload_failed");
    this.resetUploaderState();
  }

  resetUploaderState({ abortUpload = false } = {}) {
    if (abortUpload) {
      this.activeUpload?.abort();
    }

    this.activeUpload = null;
    this.latestStreamMediaId = null;
    this.isUploading = false;
    this.uploadProgress = 0;
  }

  _tusMetadata(file) {
    const metadata = {};

    if (this.keepOriginalName && file.name) {
      metadata.name = file.name;
      metadata.filename = file.name;
    }

    if (file.type) {
      metadata.filetype = file.type;
    }

    return metadata;
  }

  async _getTusUploadClass() {
    if (typeof window === "undefined") {
      return null;
    }

    // Load vendored tus-js-client if not already loaded
    if (!window.tus?.Upload) {
      await loadScript(
        "/plugins/discourse-video-stream/javascripts/tus.min.js"
      );
    }

    return window?.tus?.Upload || null;
  }

  _csrfToken() {
    if (typeof document === "undefined") {
      return null;
    }

    return document.querySelector("meta[name='csrf-token']")?.content || null;
  }

  _extractUidFromUrl(url) {
    if (!url) {
      return;
    }

    const segments = url.split("/").filter(Boolean);
    return segments[segments.length - 1];
  }

  /**
   * Upload a file directly (used for preselected files)
   * @param {File} file
   */
  uploadFile(file) {
    if (
      !this.validateFilePresence(file) ||
      !this.validateConfiguration() ||
      !this.validateExtension(file) ||
      !this.validateFileSize(file)
    ) {
      return;
    }

    try {
      this._startTusUpload(file);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Video upload failed", error);
      this.showToast("video_stream.upload_failed");
    }
  }

  /**
   * @action
   * @param {InputEvent & { target: HTMLInputElement }} event
   */
  @action
  toggleKeepOriginalName(event) {
    this.keepOriginalName = Boolean(event.target?.checked);
  }

  /**
   * @action
   * @param {InputEvent & { target: HTMLInputElement }} event
   */
  @action
  uploadVideo(event) {
    const file = event.target?.files?.[0];
    this.uploadFile(file);
    this.resetInputValue(event.target);
  }

  <template>
    <DModal
      class="video-upload-modal"
      @title={{i18n "video_stream.upload_video"}}
      @closeModal={{@closeModal}}
    >
      <:body>
        {{#if this.isUploading}}
          <div class="video-stream-upload-progress">
            <div class="progress-bar">
              <div class="progress" style={{this.progressStyle}}></div>
            </div>
            <span class="progress-text">
              {{i18n
                "video_stream.upload_progress"
                progress=this.uploadProgress
              }}
            </span>
          </div>
        {{else}}
          <div class="video-upload-content">
            <p>{{i18n "video_stream.upload_description"}}</p>
            <label class="video-stream-keep-name-label">
              <input
                type="checkbox"
                checked={{this.keepOriginalName}}
                {{on "change" this.toggleKeepOriginalName}}
              />
              <span>{{i18n "video_stream.keep_original_name"}}</span>
            </label>
            <input
              type="file"
              accept={{this.fileInputAccept}}
              class="btn btn-primary"
              {{on "change" this.uploadVideo}}
            />
          </div>
        {{/if}}
      </:body>

      <:footer>
        {{#unless this.isUploading}}
          <DButton class="btn-flat" @action={{@closeModal}} @label="cancel" />
        {{/unless}}
      </:footer>
    </DModal>
  </template>
}
