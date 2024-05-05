# frozen_string_literal: true

require 'English'
require 'cgi'

module YIParser
  class ProfileAgent
    @config = O14::Config.get_config
    @import_queue = O14::RMQ.get_channel.queue(@config.infrastructure['import_queue'], durable: true)
    @videos_exchange =  O14::RMQ.get_channel.direct(@config.infrastructure['videos_exchange'], durable: true)
    @export_exchange =  O14::RMQ.get_channel.direct(@config.infrastructure['export_exchange'], durable: true)
    @s3_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['s3_exchange'], durable: true)
    @profile_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['import_exchange'], durable: true)
    @linktree_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['linktree_exchange'], durable: true)
    @logger = O14::ProjectLogger.get_logger
    @http = HttpClient

    CHANNEL_URL = 'https://www.youtube.com/channel/'
    MAX_DAYS_TO_UPDATE = 29

    def self.db
      O14::DB.get_db
    end

    def self.logger
      O14::ProjectLogger.get_logger
    end

    def self.run
      @import_queue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, body|
        msg = JSON.parse(body, symbolize_names: true)
        if msg[:youtube_userid] && is_profile_exist(msg[:youtube_userid])
          O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
          logger.debug "account #{msg[:youtube_userid]} already exist"
          next
        end
        logger.debug msg
        process_result = process_influencer msg
        if process_result[:success]
          O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
        else
          logger.warn 'Profile process is false'
          if msg[:attempts].nil? || msg[:attempts] < 20
            msg[:attempts] = 0 if msg[:attempts].nil?
            logger.warn "try attempt #{msg[:attempts] + 1}"
            send_profile_msg(msg[:youtube_userid], msg[:attempts] + 1)
            O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
          else
            logger.warn 'msg rejected'
            O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
          end
        end
      rescue Bunny::Session
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        logger.error "#{Time.now} - Bunny::Session Error"
      rescue StandardError
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        logger.error "#{$ERROR_INFO.class.name}\n#{$ERROR_INFO.message}\n#{$ERROR_INFO.backtrace.join("\n")}"
        sleep 5
      end
    end

    def self.send_profile_msg(author_id, attempts)
      logger.debug "send id: #{author_id}"
      msg_info = {
        youtube_userid: author_id.strip,
        attempts: attempts
      }
      O14::RMQ.send_message @profile_exchange, msg_info
    end

    def self.process_influencer(msg)
      result = {
        success: true
      }
      @username = nil
      @userid = nil
      @source_table = nil

      channel_result = check_channel "/channel/#{msg[:youtube_userid]}"
      if channel_result[:success]
        channel_info = channel_result[:data][:channel_info]
        channel_info[:old_userid] = msg[:youtube_userid] if msg[:youtube_userid] != channel_info[:user_id]
        msg_info = {
          type: 'profile',
          data: {
            channel: channel_info,
            emails: channel_result[:data][:emails]
          }
        }
        if channel_info[:subscribers_count] && channel_info[:subscribers_count] >= 1000
          processed_info = process_channel channel_info, 'discovery'

          msg_info[:data] = processed_info[:channel_info]

          if processed_info[:channel_info][:subscribers_count] && processed_info[:channel_info][:subscribers_count] >= 1000
            if processed_info[:channel_info][:profile_picture]
              send_s3_msg processed_info[:channel_info][:user_id], processed_info[:channel_info][:profile_picture]
            end

            O14::RMQ.send_message @videos_exchange, processed_info[:video_info]
          end

          if channel_result[:data][:linktree_nickname]
            send_linktree_msg(channel_info[:user_id], channel_result[:data][:linktree_nickname])
          end
        end
        O14::RMQ.send_message @export_exchange, msg_info
      elsif channel_result[:error] == 'ban'
        result[:success] = false
      elsif channel_result[:error] == 'redirected user_id exist'
        logger.debug channel_result[:error]
        msg_info = {
          type: 'old_userid',
          data: {
            old_userid: msg[:youtube_userid],
            userid: channel_result[:user_id]
          }
        }
        O14::RMQ.send_message @export_exchange, msg_info
      else
        logger.debug channel_result[:error]
      end

      result
    end

    def self.send_linktree_msg(userid, nickname)
      msg = {
        type: 'profile',
        data: {
          nickname: nickname,
          userid: userid
        }
      }
      O14::RMQ.send_message @linktree_exchange, msg
    end

    def self.is_profile_exist(user_id)
      profile = db[:youtubeinfluencers].where(userid: user_id).or(old_userid: user_id).select(:id, :updatedat).first
      if profile
        days_passed = (Time.now - profile[:updatedat]) / 60 / 60 / 24
        return true if days_passed < MAX_DAYS_TO_UPDATE
      end
      false
    end

    def self.get_videos_info(url)
      @logger.info "#{url}/videos"
      init_data = @http.get_yt_init_data "#{url}/videos?cbrd=1&ucbcb=1"

      parse_profile_videos(init_data)
    end

    def self.parse_profile_videos(init_data)
      videos = { video_ids: [], avg_post_interval: -1 }
      main_content_item = nil
      if init_data['contents']['twoColumnBrowseResultsRenderer']['tabs'][1] && (init_data['contents']['twoColumnBrowseResultsRenderer']['tabs'][1]['tabRenderer'])
        main_content_item = init_data['contents']['twoColumnBrowseResultsRenderer']['tabs'][1]['tabRenderer']['content']
      end
      if main_content_item.nil?
        # No videos in channel. Only songs
        return videos
      end

      videos_items = begin
        main_content_item['sectionListRenderer']['contents'][0]
      rescue StandardError
        nil
      end
      if videos_items
        get_section_list_renderer_videos videos_items
      else
        get_rich_grid_renderervideos main_content_item
      end
    end

    def self.get_rich_grid_renderervideos(main_content_item)
      all_videos_items = []
      main_content_item['richGridRenderer']['contents'][0..11].each do |_e|
        all_videos_items.push(_e['richItemRenderer']['content']) if _e['richItemRenderer']
      end
      get_video_info all_videos_items
    end

    def self.get_section_list_renderer_videos(videos_items)
      if videos_items['itemSectionRenderer'].nil?
        @logger.error('No videos and songs in channel')
        return { video_ids: [], avg_post_interval: -1 }
      end
      shelfRenderer_item = videos_items['itemSectionRenderer']['contents'][0]['shelfRenderer']
      shelfRenderer_item = videos_items['itemSectionRenderer']['contents'][0]['gridRenderer'] if shelfRenderer_item.nil?
      if shelfRenderer_item.nil?
        # No videos and songs in channel
        @logger.error('No videos and songs in channel')
        return { video_ids: [], avg_post_interval: -1 }
      end
      content_item = shelfRenderer_item['content']
      if content_item
        renderer_item = content_item['horizontalListRenderer']
        renderer_item ||= content_item['expandedShelfContentsRenderer']
      else
        renderer_item = shelfRenderer_item
      end
      all_videos_items = renderer_item['items'][0..11]
      get_video_info all_videos_items
    end

    def self.get_video_info(all_videos_items)
      first_post_date = nil
      last_post_date = nil
      video_ids = []
      all_videos_items.each do |item|
        video_renderer_item = item['gridVideoRenderer']
        video_renderer_item = item['videoRenderer'] if video_renderer_item.nil?
        if video_renderer_item.nil?
          # No videos in channel. Only songs
          @logger.error('No videos in channel. Only songs')
          return { video_ids: video_ids, avg_post_interval: -1 }
        end
        now_date = Time.new
        video_date = nil
        if video_renderer_item['thumbnailOverlays'][0]['thumbnailOverlayTimeStatusRenderer'] && video_renderer_item['thumbnailOverlays'][0]['thumbnailOverlayTimeStatusRenderer']['style'] == 'LIVE'
          video_date = Time.new
        elsif video_renderer_item['publishedTimeText']
          ago_time = video_renderer_item['publishedTimeText']['simpleText']
          video_date = Utils.time_ago_to_time ago_time, now_date
        elsif video_renderer_item['upcomingEventData']
          video_date = Time.at(video_renderer_item['upcomingEventData']['startTime'].to_i)
        end
        first_post_date = video_date if first_post_date.nil? && video_date
        last_post_date = video_date
        video_ids.push video_renderer_item['videoId']
      end
      avg_post_interval = get_avg_post_interval video_ids.count, first_post_date, last_post_date
      { video_ids: video_ids, avg_post_interval: avg_post_interval }
    end

    def self.get_avg_post_interval(posts_count, first_date, last_date)
      avg_post_interval = -1
      begin
        if posts_count.zero?
          avg_post_interval = -1
        elsif posts_count == 1
          if first_date
            avg_post_interval = (1 / ((Time.now.utc.to_i + 1 - first_date.utc.to_i) / (60 * 60 * 24))).truncate(3)
            avg_post_interval = 1 if avg_post_interval > 1
          end
        elsif first_date && last_date
          avg_post_interval = (posts_count / ((first_date.utc.to_i + 1 - last_date.utc.to_i).to_f / (60 * 60 * 24))).truncate(3)
        end
      rescue StandardError => e
        @logger.error 'failed with get_avg_post_interval'
        @logger.error "[Error]: #{e.inspect}"
      end
      avg_post_interval
    end

    def self.get_channel_urls(nickname)
      channel_urls = []
      nickname = CGI.escape(nickname)
      url = URI("https://www.youtube.com/results?search_query=#{nickname}&sp=EgIQAg%253D%253D")
      @logger.debug url
      init_data = @http.get_yt_init_data url

      channels = init_data['contents']['twoColumnSearchResultsRenderer']['primaryContents']['sectionListRenderer']['contents'][0]['itemSectionRenderer']['contents']
      channels.each do |channel_data|
        channel = channel_data['channelRenderer']
        next if channel.nil?

        channel_url = channel['navigationEndpoint']['commandMetadata']['webCommandMetadata']['url']
        @logger.debug channel_url
        channel_urls << channel_url
      end
      channel_urls
    end

    def self.check_channel(channel_url)
      begin
        url = URI("https://www.youtube.com#{channel_url}?cbrd=1&ucbcb=1")
      rescue URI::InvalidURIError
        return {
          success: false,
          error: 'Wrong url'
        }
      end
      @logger.debug "Profile url is #{url}"
      init_data = @http.get_yt_init_data url

      result = parse_channel(init_data, channel_url)
      if result[:success] == false && result[:url]
        channel_url = result[:url]
        url = URI("https://www.youtube.com#{channel_url}?cbrd=1&ucbcb=1")
        @logger.debug "Redirect profile url is #{url}"
        redirected_user_id = channel_url.split('/').last
        if is_profile_exist(redirected_user_id)
          return {
            success: false,
            error: 'redirected user_id exist',
            user_id: redirected_user_id
          }
        end
        init_data = @http.get_yt_init_data url, @proxy
        result = parse_channel(init_data, channel_url)
      end
      result
    end

    def self.parse_channel(init_data, channel_url)
      if init_data == false
        return {
          success: false,
          error: 'ban'
        }
      end
      if init_data.nil?
        return {
          success: false,
          error: 'Content not found'
        }
      end
      if init_data['header'].nil?
        if init_data['onResponseReceivedActions']&.first && init_data['onResponseReceivedActions'].first['navigateAction']
          nav_action = init_data['onResponseReceivedActions'].first['navigateAction']
          if nav_action['endpoint']
            url = begin
              nav_action['endpoint']['commandMetadata']['webCommandMetadata']['url']
            rescue StandardError
              nil
            end
            if url
              return {
                success: false,
                error: 'Redirect',
                url: url
              }
            end
          end
        end
        return {
          success: false,
          error: 'Content not found'
        }
      end
      if init_data['header']['c4TabbedHeaderRenderer'].nil?
        return {
          success: false,
          error: 'Section c4TabbedHeaderRenderer is nil'
        }
      end

      init_data['alerts']&.each do |alert|
        if alert['alertRenderer']['text']['simpleText'].match(/does not exist/)
          return {
            success: false,
            error: 'Channel does not exist'
          }
        end
        if alert['alertRenderer']['text']['simpleText'].match(/not available/)
          return {
            success: false,
            error: 'Channel is not available'
          }
        end
      end

      subscribes_info = init_data['header']['c4TabbedHeaderRenderer']['subscriberCountText']
      if subscribes_info.nil?
        return {
          success: false,
          error: 'Followers count not found'
        }
      end
      if subscribes_info['simpleText'].nil?
        return {
          success: false,
          error: 'Followers count not found 2'
        }
      end
      subscriber_count_text = subscribes_info['simpleText'].gsub(' subscribers', '')
      subscriber_count = subscriber_count_text.to_f
      subscriber_count = (subscriber_count * 1000.0).round if subscriber_count_text.match(/K/)
      subscriber_count = (subscriber_count * 1_000_000.0).round if subscriber_count_text.match(/M/)
      subscriber_count = (subscriber_count * 1_000_000_000.0).round if subscriber_count_text.match(/B/)
      subscriber_count = subscriber_count.to_i

      videos_count = nil
      videos_info = init_data['header']['c4TabbedHeaderRenderer']['videosCountText']
      if videos_info && videos_info['runs']&.first
        videos_text = videos_info['runs'].first['text']
        videos_count = videos_text.to_f
        videos_count = (videos_count * 1000.0).round if videos_text.match(/K/)
        videos_count = (videos_count * 1_000_000.0).round if videos_text.match(/M/)
        videos_count = (videos_count * 1_000_000_000.0).round if videos_text.match(/B/)
        videos_count = videos_count.to_i
      end

      external_links = []
      insta_nick = ''
      header_links = init_data['header']['c4TabbedHeaderRenderer']['headerLinks']
      if !header_links.nil? && !header_links['channelHeaderLinksRenderer'].nil?
        insta_nick = search_instagram_nickname header_links['channelHeaderLinksRenderer']['primaryLinks']
        if insta_nick.nil? && !header_links['channelHeaderLinksRenderer'].nil?
          insta_nick = search_instagram_nickname header_links['channelHeaderLinksRenderer']['secondaryLinks']
        end
        external_links = get_external_links(header_links['channelHeaderLinksRenderer']['primaryLinks']) + get_external_links(header_links['channelHeaderLinksRenderer']['secondaryLinks'])
      end

      description = begin
        init_data['metadata']['channelMetadataRenderer']['description']
      rescue StandardError
        ''
      end
      emails = process_email(description, 'bio')
      profile_picture = begin
        init_data['metadata']['channelMetadataRenderer']['avatar']['thumbnails'][0]['url']
      rescue StandardError
        nil
      end
      user_id = init_data['header']['c4TabbedHeaderRenderer']['channelId'] # TODO:
      username = begin
        init_data['header']['c4TabbedHeaderRenderer']['channelHandleText']['runs'][0]['text']
      rescue StandardError
        nil
      end
      username = username.gsub(/^@/, '') if username
      title = init_data['header']['c4TabbedHeaderRenderer']['title']
      username = title if username.nil?

      linktree_nickname = nil
      if external_links.count.positive?
        external_links_text = external_links.join(' ').gsub('%2F', '/')
        YIParser::Utils.extract_linktree_nickname external_links_text
      end

      channel_info = {
        updated_at: Time.now.utc,
        insta_username: @username,
        insta_userid: @userid,
        url: "https://www.youtube.com#{channel_url}",
        username: username,
        title: title,
        subscribers_count: subscriber_count,
        description: description,
        profile_picture: profile_picture,
        user_id: user_id,
        categories: nil, # TODO: пока не нашел
        external_links: external_links,
        source: 'sofinms',
        state: nil,
        hashtags: get_hashtags(description),
        insta_nick: insta_nick,
        source_table: @source_table,
        posts: videos_count
      }
      if subscriber_count && subscriber_count >= 1000 && @first_popular_channel.nil?
        @first_popular_channel = channel_info
      end
      {
        success: true,
        data: {
          channel_info: channel_info,
          linktree_nickname: linktree_nickname,
          emails: emails
        }
      }
    end

    def self.process_channel(channel_info, matching)
      @logger.info "Get about #{channel_info[:url]}"
      about = get_about(channel_info[:url])
      about_result = parse_about(about)

      channel_info[:views] = about_result[:views]
      channel_info[:country] = about_result[:country]
      channel_info[:verified] = about_result[:verified]
      channel_info[:is_business_email_exist] = about_result[:is_business_email_exist]
      channel_info[:original_source] = matching
      @logger.info "Get vedeos info #{channel_info[:url]}"

      videos_info = get_videos_info(channel_info[:url])
      channel_info[:video_ids] = videos_info[:video_ids]
      channel_info[:post_interval] = videos_info[:avg_post_interval]

      video_ids = channel_info[:video_ids].uniq
      msg_video = {
        youtube_userid: channel_info[:user_id],
        video_ids: video_ids,
        hashtags: channel_info[:hashtags],
        view_sum_count: 0,
        like_sum_count: 0,
        comments_sum_count: 0,
        video_count: video_ids.count,
        subscribers_count: channel_info[:subscribers_count]
      }

      {
        channel_info: channel_info,
        video_info: msg_video
      }
    end

    def self.parse_about(init_data)
      views = -1
      country = ''
      verified = false
      is_business_email_exist = false
      tabs = init_data['onResponseReceivedEndpoints'][0]['showEngagementPanelEndpoint']['engagementPanel']
      label = begin
        init_data['header']['c4TabbedHeaderRenderer']['badges'][0]['metadataBadgeRenderer']['accessibilityData']['label']
      rescue StandardError
        ''
      end
      verified = true if label == 'Verified'
      if tabs['engagementPanelSectionListRenderer']
        if tabs['engagementPanelSectionListRenderer']['header']['engagementPanelTitleHeaderRenderer']['title']['simpleText'] == 'About'
          channel_about = tabs['engagementPanelSectionListRenderer']['content']['sectionListRenderer']['contents'][0]['itemSectionRenderer']['contents'][0]['aboutChannelRenderer']['metadata']['aboutChannelViewModel']
          is_business_email_exist = true if channel_about['businessEmailRevealButton']
          # description = channel_about['channel_about']['simpleText']
          views = channel_about['viewCountText'].gsub(',', '').to_i if channel_about['viewCountText']
        end

        if tabs['engagementPanelSectionListRenderer']['content']['sectionListRenderer']['contents'][0]['itemSectionRenderer']['contents'][0]['aboutChannelRenderer']['metadata']['aboutChannelViewModel']['country'].nil?
          country = ''
        else
          country = tabs['engagementPanelSectionListRenderer']['content']['sectionListRenderer']['contents'][0]['itemSectionRenderer']['contents'][0]['aboutChannelRenderer']['metadata']['aboutChannelViewModel']['country']
        end

      end
      { views: views, country: country, verified: verified, is_business_email_exist: is_business_email_exist }
    end

    def self.get_about(channel_url)
      @http.get_yt_init_data "#{channel_url}/about?cbrd=1&ucbcb=1"
    end

    def self.get_hashtags_from_posts(posts_list)
      hashtags = []
      begin
        posts_list.each do |edge|
          edge['node']['edge_media_to_caption']['edges'].each do |e_t_c|
            post_hashtags = e_t_c['node']['text'].scan(/#\p{L}+/)
            hashtags += post_hashtags
          end
        end
        hashtags = hashtags.uniq
      rescue StandardError => e
        @logger.error 'failed with get_hashtags_from_posts'
        @logger.error "[Error]: #{e.inspect}"
      ensure
        return hashtags
      end
    end

    def self.get_hashtags(text)
      # Text.to_s needed because sometimes text should be as Symbal - :P
      text.to_s.scan(/#\S+/iu)
    end

    def self.send_s3_msg(id, original_url)
      s3_msg = {
        'youtube_userid' => id,
        'original_url' => original_url
      }
      O14::RMQ.send_message @s3_exchange, s3_msg
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

    def self.process_biography(text)
      %w[youtube youtuber].each do |word|
        matched = text.match(/#{word}\s?:\s?([@\p{Alpha}\p{M}\p{Nd}\p{Pc}\p{Join_C}_0-9\s]+?)[\n.]/i)
        next unless matched && matched[1]

        nick = matched[1].gsub('@', '')
        next if nick.length < 4
        next if %w[channel Views].include? nick

        return nick
      end
      nil
    end

    def self.get_external_links(links)
      external_links = []
      links&.each do |link|
        url = link['navigationEndpoint']['commandMetadata']['webCommandMetadata']['url']
        external_links << url
      end
      external_links
    end

    def self.search_instagram_nickname(links)
      links&.each do |link|
        next unless link['title']['simpleText'] == 'Instagram'

        url = link['navigationEndpoint']['commandMetadata']['webCommandMetadata']['url']
        begin
          nick = url.match(/instagram.com%2F(.+)/i)[1].gsub('%2F', '').gsub(/%3F.*/, '').strip
          return nick
        rescue StandardError
          @logger.error "Not processed insta url. Url is #{url}"
        end
        return
      end
      nil
    end
  end
end
