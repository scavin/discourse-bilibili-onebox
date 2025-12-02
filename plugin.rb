# name: discourse-bilibili-onebox
# about: A Discourse plugin to embed Bilibili videos
# version: 1.0
# authors: Appinn
# url: https://meta.appinn.net/t/topic/55832

# frozen_string_literal: true

require "uri"
require_dependency "final_destination"

after_initialize do
  module ::Onebox
    module Engine
      class BilibiliOnebox
        include Onebox::Engine

        REGEX = %r{\Ahttps?://(www|m)\.bilibili\.com/video/([A-Za-z0-9]+)(?:[/?#].*)?\z}
        INLINE_REGEX = /href="https?:\/\/(www|m)\.bilibili\.com\/video\/([A-Za-z0-9]+)(?:[\/?#].*)?"[^>]*?class="inline-onebox"/
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
              URI.parse(url).path.delete_prefix("/").sub(%r{/*\z}, "")
            rescue URI::InvalidURIError
              nil
            end
          return if slug.blank?

          cache_key = "bilibili-short-link:#{slug}"
          cached_video_id = Discourse.cache.read(cache_key)
          return cached_video_id if cached_video_id.present?

          begin
            resolved = FinalDestination.new(url, max_redirects: 5, timeout: 5).resolve
            video_id = extract_video_id(resolved) if resolved
            Discourse.cache.write(cache_key, video_id, expires_in: 1.day) if video_id.present?
            video_id
          rescue StandardError => e
            Rails.logger.warn("[discourse-bilibili-onebox] short link resolve failed: #{e.message}")
            nil
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

  on(:post_process_cooked) do |doc, post|
    doc.css("a[href]").each do |link|
      href = link["href"]
      begin
        uri = URI.parse(href)
      rescue URI::InvalidURIError
        next
      end
      next unless uri.host == "b23.tv"

      # 仅替换块级短链：<p><a href="https://b23.tv/xxx">https://b23.tv/xxx</a></p>
      parent = link.parent
      next unless parent&.name == "p" && parent.children.count == 1
      next unless link.text.strip == href

      video_id = ::Onebox::Engine::BilibiliOnebox.resolve_short_link(href)
      next unless video_id

      iframe = ::Onebox::Engine::BilibiliOnebox.iframe_html(video_id)
      link.replace(iframe)
    end
  end
end
