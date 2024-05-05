# frozen_string_literal: true

require 'date'

module YIParser
  class VideoProcessAgent
    MAX_RESPONSE_TIME_SEC = 12

    @config = O14::Config.get_config
    @http = HttpClient
    @export_exchange =  O14::RMQ.get_channel.direct(@config.infrastructure['export_exchange'], durable: true)
    @videos_exchange =  O14::RMQ.get_channel.direct(@config.infrastructure['videos_exchange'], durable: true)

    @videos_queue = O14::RMQ.get_channel.queue(@config.infrastructure['videos_queue'], durable: true)

    def self.run
      @videos_queue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, body|
        msg = JSON.parse(body, symbolize_names: true)
        if msg[:video_ids].count.positive?
          process_result = process_msg(msg)
          logger.debug "success #{process_result[:success]}"
          if process_result[:success]
            O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
            O14::RMQ.send_message @videos_exchange, process_result[:new_msg] if process_result[:new_msg]
          else
            logger.warn 'Video process is false, msg rejected'
            O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
            next
          end
        else
          msg[:external_tags] = [] if msg[:external_tags].nil?
          export_profile_data = {
            youtube_userid: msg[:youtube_userid],
            hashtags: msg[:hashtags].uniq,
            external_tags: msg[:external_tags].uniq,
            average_comments: 0,
            average_likes: 0,
            average_views: 0,
            engagement_per_post: 0,
            engagement_rate: 0
          }
          export_profile_msg = {
            type: 'profile_video',
            data: export_profile_data
          }
          O14::RMQ.send_message @export_exchange, export_profile_msg
          O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
        end
      rescue Bunny::Session
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        logger.error "#{Time.now} - Bunny::Session Error"
      rescue StandardError => e
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        logger.error "#{e.class.name} #{e.message}"
        logger.error "Exception Backtrace: #{e.backtrace}"
      end
    end

    def self.process_msg(msg)
      video_ids = msg[:video_ids].map { |e| e }
      logger.debug "Video count: #{video_ids.count}"
      video_id = video_ids.shift
      logger.debug "Video id: #{video_id}"
      result = {
        hashtags: [],
        external_tags: [],
        view: 0,
        like: 0,
        comment: 0
      }
      process_result = process_video(video_id, msg[:youtube_userid])
      if process_result[:success] == false
        logger.debug process_result[:error]
        if process_result[:error] == 'ban'
          return {
            success: false,
            new_msg: nil
          }
        end
        msg[:video_count] -= 1
      else
        export_data = process_result[:data][:export_data]
        msg_info = {
          type: 'video',
          data: export_data
        }
        O14::RMQ.send_message @export_exchange, msg_info

        result = process_result[:data][:result]
      end

      msg_hashtags = msg[:hashtags]
      msg_hashtags ||= []
      msg_external_tags = msg[:external_tags]
      msg_external_tags ||= []
      hashtags = msg_hashtags + result[:hashtags]
      external_tags = msg_external_tags + result[:external_tags]
      view_sum_count = msg[:view_sum_count] + result[:view]
      msg[:like_sum_count] = 0 if msg[:like_sum_count].nil?
      result[:like] = 0 if result[:like].nil?
      like_sum_count = msg[:like_sum_count] + result[:like]
      comments_sum_count = msg[:comments_sum_count] + result[:comment]
      new_msg = {
        video_ids: video_ids,
        youtube_userid: msg[:youtube_userid],
        hashtags: hashtags,
        external_tags: external_tags,
        view_sum_count: view_sum_count,
        like_sum_count: like_sum_count,
        comments_sum_count: comments_sum_count,
        video_count: msg[:video_count],
        subscribers_count: msg[:subscribers_count]
      }

      if video_ids.count.zero?
        average_likes = -1
        average_views = -1
        average_comments = -1
        if (msg[:video_count]).positive?
          average_likes = like_sum_count.to_f / msg[:video_count]
          average_views = view_sum_count.to_f / msg[:video_count]
          average_comments = comments_sum_count.to_f / msg[:video_count]
        end
        engagement_per_post = (average_likes + average_comments).round(2)
        engagement_rate = if msg[:subscribers_count] == -1 || msg[:subscribers_count].nil?
                            -1
                          else
                            (engagement_per_post.to_f / msg[:subscribers_count] * 100.0).round(2)
                          end

        export_profile_data = {
          youtube_userid: msg[:youtube_userid],
          hashtags: hashtags.uniq,
          external_tags: external_tags.uniq,
          average_comments: average_comments,
          average_likes: average_likes,
          average_views: average_views,
          engagement_per_post: engagement_per_post,
          engagement_rate: engagement_rate
        }
        export_profile_msg = {
          type: 'profile_video',
          data: export_profile_data
        }
        O14::RMQ.send_message @export_exchange, export_profile_msg
        new_msg = nil
      end

      {
        success: true,
        new_msg: new_msg
      }
    end

    def self.process_video(video_id, youtube_userid)
      url = "https://www.youtube.com/watch?v=#{video_id}"
      init_data = @http.get_yt_init_data url

      parse_video_content init_data, url, youtube_userid
    end

    def self.parse_video_content(init_data, url, youtube_userid)
      if init_data == false
        return {
          success: false,
          error: 'ban'
        }
      end
      if init_data['contents'].nil?
        return {
          success: false,
          error: 'This video is unavailable'
        }
      end
      contents = init_data['contents']['twoColumnWatchNextResults']['results']['results']['contents']
      if contents.nil?
        return {
          success: false,
          error: 'private video'
        }
      end
      if contents.to_s.match(/This video has been removed by the uploader/)
        return {
          success: false,
          error: 'video removed'
        }
      end
      if contents.to_s.match(/This video is no longer available/)
        return {
          success: false,
          error: 'video unavailable'
        }
      end
      if contents.to_s.match(/Certain features have been disabled for this video/)
        return {
          success: false,
          error: 'video with disabled features'
        }
      end
      description = ''
      videoSecondaryInfoRenderer = contents.find { |_e| !_e['videoSecondaryInfoRenderer'].nil? }
      if videoSecondaryInfoRenderer && (videoSecondaryInfoRenderer['videoSecondaryInfoRenderer']['attributedDescription'])
        description = videoSecondaryInfoRenderer['videoSecondaryInfoRenderer']['attributedDescription']['content']
      end
      renderer_item = contents[0]['videoPrimaryInfoRenderer']
      renderer_item = contents[1]['videoPrimaryInfoRenderer'] if renderer_item.nil?
      if renderer_item['badges']
        not_available = renderer_item['badges'].find do |_e|
          _e['metadataBadgeRenderer']['label'] == 'Not available'
        end
        if not_available
          return {
            success: false,
            error: 'Not available'
          }
        end
        not_available = renderer_item['badges'].find { |_e| _e['metadataBadgeRenderer']['label'] == 'Buy' }
        if not_available
          return {
            success: false,
            error: 'Paid video'
          }
        end
        not_available = renderer_item['badges'].find do |_e|
          _e['metadataBadgeRenderer']['label'] == 'Members only'
        end
        if not_available
          return {
            success: false,
            error: 'Members only'
          }
        end
        not_available = renderer_item['badges'].find do |_e|
          _e['metadataBadgeRenderer']['style'] == 'BADGE_STYLE_TYPE_YPC'
        end
        if not_available
          return {
            success: false,
            error: 'Season only'
          }
        end
      end
      title = ''
      title = renderer_item['title']['runs'][0]['text'] if renderer_item['title']['runs']
      view_count = 0
      view_count_section = renderer_item['viewCount']
      if view_count_section
        view_count_text = view_count_section['videoViewCountRenderer']['viewCount']['simpleText']
        if view_count_text.nil?
          view_count_text = view_count_section['videoViewCountRenderer']['viewCount']['runs'][0]['text']
        end
        view_count = view_count_text.gsub(' views', '').gsub(',', '').to_i
      end

      likes_count = nil
      contents.each do |_content|
        next unless _content['videoPrimaryInfoRenderer']

        _content['videoPrimaryInfoRenderer']['videoActions']['menuRenderer']['topLevelButtons'].each do |_tlb|
          if _tlb['segmentedLikeDislikeButtonRenderer']
            likes_count = _tlb['segmentedLikeDislikeButtonRenderer']['likeButton']['toggleButtonRenderer']['defaultText']['simpleText'].to_i
          end
        end
      end
      if likes_count.nil?
        tbr = renderer_item['videoActions']['menuRenderer']['topLevelButtons'][0]['toggleButtonRenderer']
        if tbr
          likes_count_text = tbr['toggledText']['accessibility']['accessibilityData']['label']
          likes_count = likes_count_text.gsub(' likes', '').gsub(',', '').to_i
        end
      end
      hashtags = []
      external_tags = []
      super_title_links = renderer_item['superTitleLink']
      if super_title_links && super_title_links['runs']
        super_title_links['runs'].each do |json|
          text = json['text'].to_s.strip
          next if text.empty? || text == '#'

          if text[0] == '#'
            hashtags.push(text)
          else
            external_tags.push(text)
          end
        end
      end
      date_text = renderer_item['dateText']['simpleText']
      begin
        date = Date.parse(date_text) # TODO: Глянуть формат в базе
      rescue StandardError
        date = Date.new
      end
      comment_count = 0
      cepr_tag = nil
      contents.each do |_content|
        next unless _content['itemSectionRenderer']

        cepr_tag = _content['itemSectionRenderer']['contents'][0]['commentsEntryPointHeaderRenderer']
        break if cepr_tag
      end
      if cepr_tag
        cc_tag = cepr_tag['commentCount']
        comment_count = cc_tag['simpleText'].to_i if cc_tag
      end
      export_data = {
        post_link: url,
        title: title,
        description: description,
        like: likes_count,
        comment: comment_count,
        view: view_count,
        posted_at: date,
        youtube_userid: youtube_userid,
        emails: process_email(description, 'post')
      }
      result = {
        hashtags: hashtags,
        external_tags: external_tags,
        view: view_count,
        comment: comment_count,
        like: likes_count
      }
      {
        success: true,
        data: {
          result: result,
          export_data: export_data
        }
      }
    end

    def self.process_email(text, source)
      influencer_emails = []
      emails = YIParser::Utils.get_all_emails(text)
      emails.each do |email|
        email = YIParser::Utils.complete_email_domain(email)
        is_correct = YIParser::Utils.is_email_syntax_correct(email)
        influencer_emails.push({
                                 email: email,
                                 source: source,
                                 is_correct: is_correct
                               })
      end
      influencer_emails
    end

    def self.logger
      O14::ProjectLogger.get_logger
    end
  end
end
