# name: discourse-bilibili-onebox
# about: A Discourse plugin to embed Bilibili videos. Modified by Jackzhang144.
# version: 1.2
# authors: Appinn
# url: https://meta.appinn.net/t/topic/55832

# frozen_string_literal: true

require "net/http"
require "uri"
require_dependency "final_destination"
register_css <<~CSS
  .bilibili-onebox {
    width: 100%;
    height: auto;
    aspect-ratio: 16/9;
  }
CSS

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
          "<iframe class='bilibili-onebox' src='https://player.bilibili.com/player.html?bvid=#{video_id}&high_quality=1&autoplay=0' scrolling='no' border='0' frameborder='no' width='100%' height='100%' allowfullscreen='true'></iframe>"
        end

        def self.extract_video_id(url)
          match = REGEX.match(url)
          match && match[2]
        end

        def self.resolve_short_link(url)
          Rails.logger.warn("[discourse-bilibili-onebox] resolve short link: #{url}")
          return unless url&.match?(SHORT_LINK_REGEX)

          slug =
            begin
              URI.parse(url).path.delete_prefix("/").sub(%r{/*\z}, "")
            rescue URI::InvalidURIError
              Rails.logger.warn("[discourse-bilibili-onebox] invalid short link url: #{url}")
              nil
            end
          return if slug.blank?

          cache_key = "bilibili-short-link:#{slug}"
          cached_video_id = Discourse.cache.read(cache_key)
          if cached_video_id.present?
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link cache hit: #{slug} -> #{cached_video_id}",
              )
            return cached_video_id
          end

          # b23 在带尾部 / 时可能返回 200 JSON (-404)，不跳转；强制使用标准化 URL 以确保 302 跳转
          normalized_url = "https://b23.tv/#{slug}"
          Rails.logger.warn(
            "[discourse-bilibili-onebox] short link normalized: #{url} -> #{normalized_url}",
            )

          log_short_link_http_response(
            normalized_url,
            max_redirects: 5,
            timeout: 5,
            headers: {
              "User-Agent" =>
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                  "(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0",
            },
          )

          begin
            resolved =
              FinalDestination.new(
                normalized_url,
                max_redirects: 5,
                timeout: 5,
                headers: {
                  "User-Agent" =>
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                      "(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0",
                },
                ).resolve
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link resolved to: #{resolved.inspect}",
              )
            video_id = extract_video_id(resolved) if resolved
            Discourse.cache.write(cache_key, video_id, expires_in: 1.day) if video_id.present?
            if video_id.present?
              Rails.logger.warn(
                "[discourse-bilibili-onebox] short link resolved: #{slug} -> #{video_id}",
                )
            else
              Rails.logger.warn(
                "[discourse-bilibili-onebox] short link resolved but no video id: #{resolved}",
                )
            end
            video_id
          rescue StandardError => e
            Rails.logger.warn("[discourse-bilibili-onebox] short link resolve failed: #{e.message}")
            nil
          end
        end

        def self.log_short_link_http_response(url, max_redirects:, timeout:, headers:)
          Rails.logger.warn(
            "[discourse-bilibili-onebox] short link http request: url=#{url} " \
              "max_redirects=#{max_redirects} timeout=#{timeout} headers=#{headers.inspect}",
            )

          current_url = url
          redirects = 0

          loop do
            uri =
              begin
                URI.parse(current_url)
              rescue URI::InvalidURIError => e
                Rails.logger.warn(
                  "[discourse-bilibili-onebox] short link http invalid uri: #{current_url} " \
                    "(#{e.message})",
                  )
                break
              end

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == "https"
            http.open_timeout = timeout
            http.read_timeout = timeout

            request = Net::HTTP::Get.new(uri.request_uri)
            headers.each { |key, value| request[key] = value }

            response = http.request(request)

            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link http response: url=#{current_url} " \
                "status=#{response.code} message=#{response.message}",
              )
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link http headers: #{response.to_hash.inspect}",
              )
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link http body:\n#{response.body}",
              )

            break unless response.is_a?(Net::HTTPRedirection)

            location = response["location"]
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link http redirect: #{current_url} -> #{location}",
              )

            break if location.blank?

            redirects += 1
            break if redirects > max_redirects

            current_url = uri.merge(location).to_s
          end
        rescue StandardError => e
          Rails.logger.warn(
            "[discourse-bilibili-onebox] short link http request failed: #{e.class} #{e.message}",
            )
        end

        # 将 raw 文本中“单独成行”的 b23 短链接展开为完整的 Bilibili 视频链接。
        def self.expand_short_links(raw)
          return raw if raw.blank?

          raw
            .lines
            .map do |line|
            newline = line.end_with?("\n") ? "\n" : ""
            content = line.delete_suffix("\n")
            stripped = content.strip
            next line unless stripped.match?(SHORT_LINK_REGEX)
            Rails.logger.warn("[discourse-bilibili-onebox] short link matched line: #{stripped}")
            video_id = resolve_short_link(stripped)
            if video_id.blank?
              Rails.logger.warn(
                "[discourse-bilibili-onebox] short link resolve returned blank: #{stripped}",
                )
              next line
            end

            leading = content[/\A\s*/]
            trailing = content[/\s*\z/]
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link expanded: #{stripped} -> #{video_id}",
              )
            "#{leading}https://www.bilibili.com/video/#{video_id}#{trailing}#{newline}"
          end
            .join
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

      classes = (link["class"] || "").split

      # 块级裸链接或 onebox 链接才替换，避免句中/列表被误替换
      parent = link.parent
      block_link =
        parent&.name == "p" &&
        parent.element_children.length == 1 &&
        parent.element_children.first == link &&
        parent.text.strip == href
      next unless block_link || classes.include?("onebox")

      case uri.host
      when "b23.tv"
        video_id = ::Onebox::Engine::BilibiliOnebox.resolve_short_link(href)
      when "www.bilibili.com", "m.bilibili.com"
        video_id = ::Onebox::Engine::BilibiliOnebox.extract_video_id(href)
      end

      next unless video_id

      iframe = ::Onebox::Engine::BilibiliOnebox.iframe_html(video_id)
      link.replace(iframe)
    end
  end

  # 发帖落库前规范化 b23 短链接。
  on(:before_create_post) do |post, _params|
    original_raw = post.raw
    expanded_raw = ::Onebox::Engine::BilibiliOnebox.expand_short_links(original_raw)
    if expanded_raw != original_raw
      Rails.logger.warn(
        "[discourse-bilibili-onebox] expanded short links before create (user_id=#{post.user_id})",
        )
    end
    post.raw = expanded_raw
  end
end
