/**
 * Custom BBCode for Cloudflare Stream video embeds
 * Converts [video-stream id="video_id"][/video-stream] to a video container that will be initialized with Shaka Player
 * Supports both inline and block formats
 */

// Validates video ID - allows alphanumeric, hyphens, and underscores only
function isValidVideoId(videoId) {
  return videoId && /^[a-zA-Z0-9_-]+$/.test(videoId);
}

function isValidProvider(provider) {
  return (
    typeof provider === "string" &&
    ["cloudflare", "bunny"].includes(provider.trim().toLowerCase())
  );
}

const blockRule = {
  tag: "video-stream",

  wrap(token, tagInfo) {
    const videoId = tagInfo.attrs?.id;

    if (!isValidVideoId(videoId)) {
      return false;
    }

    const attrs = [
      ["class", "video-stream-container"],
      ["data-video-id", videoId],
    ];

    const provider = tagInfo.attrs?.provider;
    if (isValidProvider(provider)) {
      attrs.push(["data-provider", provider.trim().toLowerCase()]);
    }

    token.attrs = attrs;

    return true;
  },
};

const inlineRule = {
  tag: "video-stream",

  replace(state, tagInfo) {
    const videoId = tagInfo.attrs?.id;

    if (!isValidVideoId(videoId)) {
      return false;
    }

    const provider = tagInfo.attrs?.provider;
    const providerAttr = isValidProvider(provider)
      ? ` data-provider="${provider.trim().toLowerCase()}"`
      : "";

    let token = state.push("html_inline", "", 0);
    token.content = `<div class="video-stream-container" data-video-id="${videoId}"${providerAttr}></div>`;

    return true;
  },
};

export function setup(helper) {
  helper.allowList([
    "div.video-stream-container",
    "div[data-video-id]",
    "div[data-provider]",
    "video.video-stream-player",
    "video[controls]",
    "video[autoplay]",
    "video[poster]",
  ]);

  helper.registerPlugin((md) => {
    md.block.bbcode.ruler.push("video-stream", blockRule);
    md.inline.bbcode.ruler.push("video-stream", inlineRule);
  });
}
