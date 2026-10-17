import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

/**
 * @component live-stream-modal
 * @param {{ toolbarEvent?: { addText?: (value: string) => void } }} this.args.model
 */
export default class LiveStreamModal extends Component {
  @service toasts;
  @service siteSettings;

  /**
   * @type {boolean}
   */
  @tracked isCreating = false;

  /**
   * @type {{ uid: string, rtmps_url: string, rtmps_stream_key: string } | null}
   */
  @tracked liveInput = null;

  /**
   * @type {boolean}
   */
  @tracked hasCopiedUrl = false;

  /**
   * @type {boolean}
   */
  @tracked hasCopiedKey = false;

  /**
   * Insert the video embed BBCode into the composer
   * @action
   */
  @action
  insertEmbed() {
    const toolbarEvent = this.args.model?.toolbarEvent;

    if (!toolbarEvent?.addText) {
      this.toasts.error({
        duration: "short",
        data: { message: i18n("video_stream.missing_toolbar_event") },
      });
      return;
    }

    const uid = this.liveInput?.uid;
    if (!uid) {
      return;
    }

    const provider = this.siteSettings.video_stream_provider || "cloudflare";
    const bbcode = `\n\n[video-stream id="${uid}" provider="${provider}"]\n[/video-stream]\n\n`;

    toolbarEvent.addText(bbcode);
    this.args.closeModal?.();
  }

  /**
   * Create a new live input via the API
   * @action
   */
  @action
  async createLiveStream() {
    this.isCreating = true;

    try {
      const response = await ajax("/video-stream/create-live-stream.json", {
        type: "POST",
        data: {
          name: `Discourse Live Stream - ${new Date().toISOString()}`,
        },
      });

      this.liveInput = response;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isCreating = false;
    }
  }

  /**
   * Copy text to clipboard
   * @param {string} text
   * @param {"url" | "key"} type
   * @action
   */
  @action
  async copyToClipboard(text, type) {
    try {
      await navigator.clipboard.writeText(text);

      if (type === "url") {
        this.hasCopiedUrl = true;
        setTimeout(() => {
          this.hasCopiedUrl = false;
        }, 2000);
      } else if (type === "key") {
        this.hasCopiedKey = true;
        setTimeout(() => {
          this.hasCopiedKey = false;
        }, 2000);
      }

      this.toasts.success({
        duration: "short",
        data: { message: i18n("video_stream.copied_to_clipboard") },
      });
    } catch {
      this.toasts.error({
        duration: "short",
        data: { message: i18n("video_stream.copy_failed") },
      });
    }
  }

  <template>
    <DModal
      class="live-stream-modal"
      @title={{i18n "video_stream.create_live_stream"}}
      @closeModal={{@closeModal}}
    >
      <:body>
        {{#if this.liveInput}}
          <div class="live-stream-credentials">
            <p class="live-stream-instructions">
              {{i18n "video_stream.live_stream_instructions"}}
            </p>

            <div class="credential-group">
              <label class="credential-label">
                {{i18n "video_stream.rtmps_url"}}
              </label>
              <div class="credential-row">
                <input
                  type="text"
                  readonly
                  value={{this.liveInput.rtmps_url}}
                  class="credential-input"
                />
                <DButton
                  @icon={{if this.hasCopiedUrl "check" "copy"}}
                  @action={{fn
                    this.copyToClipboard
                    this.liveInput.rtmps_url
                    "url"
                  }}
                  @label={{if
                    this.hasCopiedUrl
                    "video_stream.copied"
                    "video_stream.copy"
                  }}
                  class="btn-small"
                />
              </div>
            </div>

            <div class="credential-group">
              <label class="credential-label">
                {{i18n "video_stream.rtmps_stream_key"}}
              </label>
              <div class="credential-row">
                <input
                  type="text"
                  readonly
                  value={{this.liveInput.rtmps_stream_key}}
                  class="credential-input"
                />
                <DButton
                  @icon={{if this.hasCopiedKey "check" "copy"}}
                  @action={{fn
                    this.copyToClipboard
                    this.liveInput.rtmps_stream_key
                    "key"
                  }}
                  @label={{if
                    this.hasCopiedKey
                    "video_stream.copied"
                    "video_stream.copy"
                  }}
                  class="btn-small"
                />
              </div>
            </div>

            <div class="alert alert-warning">
              {{i18n "video_stream.live_stream_warning"}}
            </div>
          </div>
        {{else}}
          <div class="live-stream-create">
            <p>{{i18n "video_stream.live_stream_description"}}</p>
          </div>
        {{/if}}
      </:body>

      <:footer>
        {{#if this.liveInput}}
          <DButton
            @action={{this.insertEmbed}}
            @label="video_stream.insert_embed"
            class="btn-primary"
          />
          <DButton @action={{@closeModal}} @label="close" class="btn-flat" />
        {{else}}
          <DButton
            @action={{this.createLiveStream}}
            @label="video_stream.create"
            @disabled={{this.isCreating}}
            class="btn-primary"
          />
          <DButton
            @action={{@closeModal}}
            @label="cancel"
            @disabled={{this.isCreating}}
            class="btn-flat"
          />
        {{/if}}
      </:footer>
    </DModal>
  </template>
}
