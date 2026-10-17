# frozen_string_literal: true

describe PrettyText do
  before { Jobs.run_immediately! }

  context "with video-stream BBCode" do
    before { SiteSetting.video_stream_enabled = true }

    it "converts video-stream BBCode to video container div" do
      markdown = <<~MD
        Check out this video:

        [video-stream id="abc123def456"][/video-stream]

        Pretty cool!
      MD

      cooked = PrettyText.cook(markdown.strip)

      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include('data-video-id="abc123def456"')
    end

    it "handles video IDs with hyphens and underscores" do
      markdown = '[video-stream id="test_video-123"][/video-stream]'

      cooked = PrettyText.cook(markdown)

      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include('data-video-id="test_video-123"')
    end

    it "handles multiple video embeds in the same post" do
      markdown = <<~MD
        First video:

        [video-stream id="video1"][/video-stream]

        Second video:

        [video-stream id="video2"][/video-stream]
      MD

      cooked = PrettyText.cook(markdown.strip)

      expect(cooked).to include('data-video-id="video1"')
      expect(cooked).to include('data-video-id="video2"')
      expect(cooked.scan(/<div class="video-stream-container"/).count).to eq(2)
    end

    it "handles BBCode without quotes around attribute value" do
      markdown = "[video-stream id=abc123][/video-stream]"

      cooked = PrettyText.cook(markdown)

      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include('data-video-id="abc123"')
    end

    it "does not process BBCode with invalid characters in ID" do
      markdown = '[video-stream id="test@video"][/video-stream]' # @ is not allowed

      cooked = PrettyText.cook(markdown)

      expect(cooked).not_to include('<div class="video-stream-container"')
    end

    it "preserves surrounding content" do
      markdown = <<~MD
        Here is some text before.

        [video-stream id="abc123"][/video-stream]

        And some text after.
      MD

      cooked = PrettyText.cook(markdown.strip)

      expect(cooked).to include("Here is some text before.")
      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include("And some text after.")
    end

    it "works inline with other content" do
      markdown =
        "Watch this: [video-stream id=\"demo123\"][/video-stream] and tell me what you think!"

      cooked = PrettyText.cook(markdown)

      expect(cooked).to include("Watch this:")
      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include("and tell me what you think!")
    end

    it "handles block-style format with newline after opening tag" do
      markdown = <<~MD
        [video-stream id="block123"]
        [/video-stream]
      MD

      cooked = PrettyText.cook(markdown.strip)

      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include('data-video-id="block123"')
    end

    it "handles block-style format in context" do
      markdown = <<~MD
        Here is a video:

        [video-stream id="test456"]
        [/video-stream]

        What do you think?
      MD

      cooked = PrettyText.cook(markdown.strip)

      expect(cooked).to include("Here is a video:")
      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include('data-video-id="test456"')
      expect(cooked).to include("What do you think?")
    end

    it "handles mixed inline and block formats" do
      markdown = <<~MD
        Inline: [video-stream id="inline1"][/video-stream]

        Block:
        [video-stream id="block1"]
        [/video-stream]
      MD

      cooked = PrettyText.cook(markdown.strip)

      expect(cooked).to include('data-video-id="inline1"')
      expect(cooked).to include('data-video-id="block1"')
      expect(cooked.scan(/<div class="video-stream-container"/).count).to eq(2)
    end

    it "preserves bunny provider attribute when present in BBCode" do
      markdown = '[video-stream id="bunny123" provider="bunny"][/video-stream]'
      cooked = PrettyText.cook(markdown)

      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include('data-video-id="bunny123"')
      expect(cooked).to include('data-provider="bunny"')
    end

    it "preserves cloudflare provider attribute when present in BBCode" do
      markdown = '[video-stream id="cf123" provider="cloudflare"][/video-stream]'
      cooked = PrettyText.cook(markdown)

      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include('data-video-id="cf123"')
      expect(cooked).to include('data-provider="cloudflare"')
    end

    it "ignores invalid provider attributes" do
      markdown = '[video-stream id="test123" provider="invalid"][/video-stream]'
      cooked = PrettyText.cook(markdown)

      expect(cooked).to include('<div class="video-stream-container"')
      expect(cooked).to include('data-video-id="test123"')
      expect(cooked).not_to include("data-provider")
    end
  end
end
