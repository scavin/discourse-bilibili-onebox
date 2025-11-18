# frozen_string_literal: true

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
        matches_regexp Regexp.union(REGEX, INLINE_REGEX)

        def to_html
          match = REGEX.match(@url) || INLINE_REGEX.match(@url)
          return unless match

          video_id = match[2]
          "<iframe src='https://player.bilibili.com/player.html?bvid=#{video_id}&high_quality=1&autoplay=0' scrolling='no' border='0' frameborder='no' width='100%' height='430' allowfullscreen='true'></iframe>"
        end
      end
    end
  end
end
