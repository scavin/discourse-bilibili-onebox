# name: discourse-bilibili-onebox
# about: A Discourse plugin to embed Bilibili videos. Modified by Jackzhang144.
# version: 1.3
# authors: Appinn, modified by Jackzhang144.

# frozen_string_literal: true

require "json"
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
        LIVE_REGEX = %r{\Ahttps?://live\.bilibili\.com/(?:blanc/)?(\d+)(?:[/?#].*)?\z}
        LIVE_INLINE_REGEX = /href="https?:\/\/live\.bilibili\.com\/(?:blanc\/)?(\d+)(?:[\/?#].*)?"[^>]*?class="inline-onebox"/
        matches_regexp Regexp.union(REGEX, INLINE_REGEX, LIVE_REGEX, LIVE_INLINE_REGEX)

        def self.iframe_html(video_id)
          "<iframe class='bilibili-onebox' src='https://player.bilibili.com/player.html?bvid=#{video_id}&high_quality=1&autoplay=0' scrolling='no' border='0' frameborder='no' width='100%' height='100%' allowfullscreen='true'></iframe>"
        end

        def self.extract_video_id(url)
          match = REGEX.match(url)
          match && match[2]
        end

        def self.extract_live_room_id(url)
          match = LIVE_REGEX.match(url)
          match && match[1]
        end

        def self.live_iframe_html(room_id)
          "<iframe class='bilibili-onebox' " \
            "src='https://www.bilibili.com/blackboard/live/live-activity-player.html?cid=#{room_id}&quality=0' " \
            "scrolling='no' border='0' frameborder='no' width='100%' height='100%' " \
            "allow='autoplay; encrypted-media' allowfullscreen='true'></iframe>"
        end

        def self.resolve_live_room_id(input_id)
          return if input_id.blank?

          cache_key = "bilibili-live-room:#{input_id}"
          cached_room_id = Discourse.cache.read(cache_key)
          if cached_room_id.present?
            Rails.logger.warn(
              "[discourse-bilibili-onebox] live room cache hit: #{input_id} -> #{cached_room_id}",
              )
            return cached_room_id
          end
          Rails.logger.warn("[discourse-bilibili-onebox] live room cache miss: #{cache_key}")

          api_url = URI.parse("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=#{input_id}")
          request_headers = {
            "User-Agent" =>
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                "(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0",
            "Accept" => "application/json",
          }

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            response =
              FinalDestination::HTTP.start(
                api_url.host,
                api_url.port,
                use_ssl: api_url.scheme == "https",
                open_timeout: 5,
                read_timeout: 5,
              ) do |http|
                request = FinalDestination::HTTP::Get.new(api_url.request_uri, request_headers)
                http.request(request)
              end
            duration_ms =
              ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

            unless response.is_a?(Net::HTTPSuccess)
              Rails.logger.warn(
                "[discourse-bilibili-onebox] live room api http error: status=#{response.code} " \
                  "duration_ms=#{duration_ms} input_id=#{input_id}",
                )
              return
            end

            payload = ::JSON.parse(response.body)
            code = payload["code"]
            msg = payload["msg"]
            data = payload["data"]
            real_room_id = data.is_a?(Hash) ? data["room_id"] : nil
            short_id = data.is_a?(Hash) ? data["short_id"] : nil

            if code == 0 && real_room_id.present?
              Discourse.cache.write(cache_key, real_room_id, expires_in: 1.day)
              if short_id.present? && short_id.to_s != "0" && short_id.to_s != real_room_id.to_s
                Rails.logger.warn(
                  "[discourse-bilibili-onebox] live room resolved short id: #{input_id} -> #{real_room_id} " \
                    "(short_id=#{short_id} duration_ms=#{duration_ms})",
                  )
              else
                Rails.logger.warn(
                  "[discourse-bilibili-onebox] live room resolved: #{input_id} -> #{real_room_id} " \
                    "(duration_ms=#{duration_ms})",
                  )
              end
              return real_room_id
            end

            Rails.logger.warn(
              "[discourse-bilibili-onebox] live room api error: code=#{code.inspect} msg=#{msg.inspect} " \
                "input_id=#{input_id} duration_ms=#{duration_ms}",
              )
            nil
          rescue StandardError => e
            duration_ms =
              ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)
            Rails.logger.warn(
              "[discourse-bilibili-onebox] live room api failed: #{e.class} #{e.message} " \
                "input_id=#{input_id} duration_ms=#{duration_ms} backtrace=#{Array(e.backtrace).first(3).inspect}",
              )
            nil
          end
        end

        def self.resolve_short_link(url)
          Rails.logger.warn("[discourse-bilibili-onebox] resolve short link: #{url}")
          return unless url&.match?(SHORT_LINK_REGEX)

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          slug =
            begin
              URI.parse(url).path.delete_prefix("/").sub(%r{/*\z}, "")
            rescue URI::InvalidURIError
              Rails.logger.warn("[discourse-bilibili-onebox] invalid short link url: #{url}")
              nil
            end
          return if slug.blank?
          Rails.logger.warn("[discourse-bilibili-onebox] short link slug: #{slug}")

          cache_key = "bilibili-short-link:#{slug}"
          cached_video_id = Discourse.cache.read(cache_key)
          if cached_video_id.present?
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link cache hit: #{slug} -> #{cached_video_id}",
              )
            return cached_video_id
          end
          Rails.logger.warn("[discourse-bilibili-onebox] short link cache miss: #{cache_key}")

          # b23 在带尾部 / 时可能返回 200 JSON (-404)，不跳转；强制使用标准化 URL 以确保 302 跳转
          normalized_url = "https://b23.tv/#{slug}"
          Rails.logger.warn(
            "[discourse-bilibili-onebox] short link normalized: #{url} -> #{normalized_url}",
            )

          begin
            request_headers = {
              "User-Agent" =>
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                  "(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0",
            }
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link request options: " \
                "http_verb=get max_redirects=5 timeout=5 headers=#{request_headers.inspect}",
              )

            fd =
              FinalDestination.new(
                normalized_url,
                max_redirects: 5,
                timeout: 5,
                http_verb: :get,
                headers: request_headers,
                )
            resolved = fd.resolve
            duration_ms =
              ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link resolved to: #{resolved.inspect} " \
                "(status=#{fd.status} status_code=#{fd.status_code} content_type=#{fd.content_type} " \
                "redirected=#{fd.redirected?} hostname=#{fd.hostname} cookie=#{fd.cookie.inspect} " \
                "ignored=#{fd.ignored.inspect} duration_ms=#{duration_ms})",
              )
            video_id = extract_video_id(resolved) if resolved
            Discourse.cache.write(cache_key, video_id, expires_in: 1.day) if video_id.present?
            if video_id.present?
              Rails.logger.warn(
                "[discourse-bilibili-onebox] short link resolved: #{slug} -> #{video_id}",
                )
            else
              Rails.logger.warn(
                "[discourse-bilibili-onebox] short link resolved but no video id: #{resolved.inspect}",
                )
            end
            video_id
          rescue StandardError => e
            Rails.logger.warn(
              "[discourse-bilibili-onebox] short link resolve failed: #{e.class} #{e.message} " \
                "backtrace=#{Array(e.backtrace).first(3).inspect}",
              )
            nil
          end
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

        # 将 raw 文本中“单独成行”的直播链接短号转换为真实房间号（保留原有查询参数）。
        def self.expand_live_short_links(raw)
          return raw if raw.blank?

          raw
            .lines
            .map do |line|
            newline = line.end_with?("\n") ? "\n" : ""
            content = line.delete_suffix("\n")
            stripped = content.strip
            match = LIVE_REGEX.match(stripped)
            next line unless match
            input_id = match[1]
            room_id = resolve_live_room_id(input_id)
            next line if room_id.blank? || room_id.to_s == input_id.to_s

            leading = content[/\A\s*/]
            trailing = content[/\s*\z/]

            begin
              uri = URI.parse(stripped)
              new_path = uri.path.sub(%r{/\d+}, "/#{room_id}")
              next line if new_path == uri.path
              uri.path = new_path
              expanded = "#{leading}#{uri}#{trailing}#{newline}"
              Rails.logger.warn(
                "[discourse-bilibili-onebox] live link expanded: #{stripped} -> #{uri}",
                )
              expanded
            rescue URI::InvalidURIError
              line
            end
          end
            .join
        end

        def to_html
          video_match = REGEX.match(@url) || INLINE_REGEX.match(@url)
          if video_match
            video_id = video_match[2]
            return self.class.iframe_html(video_id)
          end

          live_match = LIVE_REGEX.match(@url) || LIVE_INLINE_REGEX.match(@url)
          if live_match
            input_id = live_match[1]
            room_id = self.class.resolve_live_room_id(input_id)
            return self.class.live_iframe_html(room_id) if room_id.present?
          end

          nil
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
      when "live.bilibili.com"
        input_id = ::Onebox::Engine::BilibiliOnebox.extract_live_room_id(href)
        room_id = ::Onebox::Engine::BilibiliOnebox.resolve_live_room_id(input_id) if input_id
      end

      iframe =
        if video_id
          ::Onebox::Engine::BilibiliOnebox.iframe_html(video_id)
        elsif room_id
          ::Onebox::Engine::BilibiliOnebox.live_iframe_html(room_id)
        end
      next unless iframe
      link.replace(iframe)
    end
  end

  # 发帖落库前规范化 b23 短链接。
  on(:before_create_post) do |post, _params|
    original_raw = post.raw
    expanded_raw = ::Onebox::Engine::BilibiliOnebox.expand_short_links(original_raw)
    expanded_raw = ::Onebox::Engine::BilibiliOnebox.expand_live_short_links(expanded_raw)
    if expanded_raw != original_raw
      Rails.logger.warn(
        "[discourse-bilibili-onebox] expanded links before create (user_id=#{post.user_id})",
        )
    end
    post.raw = expanded_raw
  end

  # 实现思路与过程：
  # 1) Discourse 的 :before_edit_post 回调触发时，post 已经被写入，修改 fields[:raw] 无法入库；
  # 2) 因此改为在 PostRevisor#revise! 最早阶段规范化短链，确保进入标准的校验/修订/烘焙流程；
  # 3) 通过 prepend 覆盖 revise!，只在 raw 中存在短链时才转换并记录日志，避免影响其它编辑；
  # 4) 最后调用 super 让原有编辑流程继续执行，保证兼容性与一致性。
  module ::DiscourseBilibiliOnebox
    module PostRevisorPatch
      def revise!(editor, fields, opts = {})
        raw = fields[:raw] || fields["raw"]
        if raw.present?
          matched_lines = raw.lines.count do |line|
            stripped = line.strip
            stripped.match?(::Onebox::Engine::BilibiliOnebox::SHORT_LINK_REGEX) ||
              stripped.match?(::Onebox::Engine::BilibiliOnebox::LIVE_REGEX)
          end
          if matched_lines > 0
            editor_id = editor&.id
            editor_username = editor&.username
            Rails.logger.warn(
              "[discourse-bilibili-onebox] before revise expand links " \
                "(post_id=#{@post&.id} user_id=#{@post&.user_id} editor_id=#{editor_id} " \
                "editor_username=#{editor_username} raw_bytes=#{raw.bytesize} " \
                "matched_lines=#{matched_lines})",
              )

            # 提前规范化短链，确保编辑走标准的校验/修订/烘焙流程。
            expanded_raw = ::Onebox::Engine::BilibiliOnebox.expand_short_links(raw)
            expanded_raw = ::Onebox::Engine::BilibiliOnebox.expand_live_short_links(expanded_raw)
            if expanded_raw != raw
              Rails.logger.warn(
                "[discourse-bilibili-onebox] expanded links before revise " \
                  "(post_id=#{@post&.id} user_id=#{@post&.user_id} editor_id=#{editor_id} " \
                  "editor_username=#{editor_username} raw_bytes=#{raw.bytesize} " \
                  "expanded_bytes=#{expanded_raw.bytesize})",
                )
              fields = fields.dup
              fields[:raw] = expanded_raw
              fields["raw"] = expanded_raw if fields.key?("raw")
            else
              Rails.logger.warn(
                "[discourse-bilibili-onebox] no links expanded before revise " \
                  "(post_id=#{@post&.id} user_id=#{@post&.user_id} editor_id=#{editor_id} " \
                  "editor_username=#{editor_username})",
                )
            end
          end
        end

        super(editor, fields, opts)
      end
    end
  end

  # 避免重复 prepend 导致调用链混乱。
  unless ::PostRevisor.ancestors.include?(::DiscourseBilibiliOnebox::PostRevisorPatch)
    ::PostRevisor.prepend(::DiscourseBilibiliOnebox::PostRevisorPatch)
  end
end
