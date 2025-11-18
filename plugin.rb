# frozen_string_literal: true

require "uri"
require_dependency "final_destination"

# name: discourse-bilibili-onebox
# about: A Discourse plugin to embed Bilibili videos
# version: 0.2
# authors: Appinn
# url: https://meta.appinn.net/t/topic/55832

after_initialize do
  module ::Onebox
    module Engine
      class BilibiliOnebox
        include Onebox::Engine

        REGEX = /https?:\/\/(www|m)\.bilibili\.com\/video\/([A-Za-z0-9]+)(?:\/|\/?\?.*)?/
        INLINE_REGEX = /href="https?:\/\/(www|m)\.bilibili\.com\/video\/([A-Za-z0-9]+)(?:\/|\/?\?.*)?"[^>]*?class="inline-onebox"/
        SHORT_LINK_REGEX = %r{\Ahttps?://b23\.tv/[A-Za-z0-9]+/?(?:\?.*)?\z}
        matches_regexp Regexp.union(REGEX, INLINE_REGEX)

        def self.iframe_html(video_id)
          "<iframe src='https://player.bilibili.com/player.html?bvid=#{video_id}&high_quality=1&autoplay=0' scrolling='no' border='0' frameborder='no' width='100%' height='430' allowfullscreen='true'></iframe>"
        end

        def self.extract_video_id(url)
          match = REGEX.match(url)
          match && match[2]
        end

        def self.resolve_short_link(url)
          return unless url&.match?(SHORT_LINK_REGEX)

          slug =
            begin
              URI.parse(url).path.delete_prefix("/")
            rescue URI::InvalidURIError
              nil
            end
          return if slug.blank?

          cache_key = "bilibili-short-link:#{slug}"

          Discourse.cache.fetch(cache_key, expires_in: 1.day) do
            begin
              resolved = FinalDestination.new(url, max_redirects: 5, timeout: 2).resolve
              extract_video_id(resolved) if resolved
            rescue StandardError => e
              Rails.logger.warn("[discourse-bilibili-onebox] short link resolve failed: #{e.message}")
              nil
            end
          end
        end

        def to_html
          match = REGEX.match(@url) || INLINE_REGEX.match(@url)
          return unless match

          video_id = match[2]
          self.class.iframe_html(video_id)
        end
      end
    end
  end

  DiscourseEvent.on(:post_process_cooked) do |doc, post|
    doc.css("a[href*='b23.tv']").each do |link|
      href = link["href"]
      video_id = ::Onebox::Engine::BilibiliOnebox.resolve_short_link(href)
      next unless video_id

      iframe = ::Onebox::Engine::BilibiliOnebox.iframe_html(video_id)
      link.replace(iframe)
    end
  end
end
