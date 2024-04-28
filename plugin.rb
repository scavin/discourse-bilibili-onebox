# frozen_string_literal: true

# name: discourse-bilibili-onebox
# about: A Discourse plugin to embed Bilibili videos
# version: 0.2
# authors: Appinn
# url: https://github.com/scavin/discourse-bilibili-onebox/

after_initialize do
  module ::Onebox
    module Engine
      class BilibiliOnebox
        include Onebox::Engine

        REGEX = /^https?:\/\/(www|m)\.bilibili\.com\/video\/(.*?)(?=\/|\?|$)/
        matches_regexp REGEX

        def to_html
          video_id = @url.match(REGEX)[2]
          "<iframe src='https://player.bilibili.com/player.html?bvid=#{video_id}&high_quality=1&autoplay=0' scrolling='no' border='0' frameborder='no' width='100%' height='430' allowfullscreen='true'></iframe>"
        end
      end
    end
  end
end
