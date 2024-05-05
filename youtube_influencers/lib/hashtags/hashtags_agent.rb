# frozen_string_literal: true

require 'English'
module YIParser
  class HashtagsAgent
    @config = O14::Config.get_config

    @hashtags_gueue = O14::RMQ.get_channel.queue(@config.infrastructure['hashtag_import_queue'], durable: true)
    @hashtags_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['hashtag_import_exchange'], durable: true)

    @profile_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['import_exchange'], durable: true)
    @profile_queue = O14::RMQ.get_channel.queue(@config.infrastructure['import_queue'], durable: true)
    @export_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['export_exchange'], durable: true)

    MESSAGE_LIMIT_IN_QUEUE = 400
    MIN_FOLLOWER_COUNT = 1000
    SEARCH_PAGES_LIMIT = 100
    SEARCH_TYPE = 'channels'
    MAX_DAYS_TO_UPDATE = 400

    def self.logger
      O14::ProjectLogger.get_logger
    end

    def self.db
      O14::DB.get_db
    end

    def self.run
      logger.debug 'Start agent'
      @hashtags_gueue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, body|
        queue_message_count = @profile_queue.message_count
        if queue_message_count >= MESSAGE_LIMIT_IN_QUEUE
          O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
          logger.debug("queue_message_count = #{queue_message_count}, im sleep 5 sec")
          sleep 5
          next
        end
        # proxy = ProxiesManager.get_free_hashtags_proxy
        # if proxy.nil?
        #   O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        #   logger.debug 'No proxies. Sleeping 5 sec...'
        #   sleep 5
        #   next
        # end

        msg = JSON.parse(body, symbolize_names: true)
        #logger.debug proxy
        # @proxy = proxy
        result = get_profiles_from_page msg[:properties], msg[:hashtag]
        if result[:success]
          logger.debug "profile ids #{result[:profile_ids].count}, page #{msg[:page_number]}"
          exist_profile_ids = get_exist_profile_ids(result[:profile_ids])
          send_add_tag_message(exist_profile_ids, msg[:hashtag]) if exist_profile_ids.count.positive?

          uniq_profile_ids = if msg[:source] && msg[:source] == 'handmade'
                               result[:profile_ids]
                             else
                               result[:profile_ids] - exist_profile_ids
                             end

          send_profiles_to_queue uniq_profile_ids if uniq_profile_ids.count.positive?
          if result[:profile_ids].count.positive? && msg[:page_number] < SEARCH_PAGES_LIMIT
            send_hashtag_msg(msg[:hashtag], msg[:source], result[:properties], msg[:page_number] + 1)
          end
          O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
        else
          logger.error result[:error]
          O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        end
      rescue Bunny::Session
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        logger.error "#{Time.now} - Bunny::Session Error"
      rescue StandardError
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        logger.error "#{$ERROR_INFO.class.name}\n#{$ERROR_INFO.message}\n#{$ERROR_INFO.backtrace.join("\n")}"
      end
    end

    def self.send_add_tag_message(profile_ids, hashtag)
      hashtag = hashtag.gsub(/\p{Z}/, '_')
      msg_info = {
        type: 'add_profile_hashtag',
        data: {
          user_ids: profile_ids,
          hashtag: hashtag
        }
      }
      O14::RMQ.send_message(@export_exchange, msg_info)
    end

    def self.get_exist_profile_ids(profile_ids)
      db[:youtubeinfluencers].select(:userid).where(userid: profile_ids).all.map { |_e| _e[:userid] }
    end

    def self.remove_exist_profile_ids(profile_ids)
      exist_rows = db[:youtubeinfluencers].select(:userid, :updatedat).where(userid: profile_ids).all
      exist_ids = []
      exist_rows.each do |row|
        days_passed = (Time.now - row[:updatedat]) / 60 / 60 / 24
        exist_ids.push(row[:userid]) if days_passed < MAX_DAYS_TO_UPDATE
      end
      profile_ids - exist_ids
    end

    def self.send_profiles_to_queue(profile_ids)
      profile_ids.each do |profile_id|
        send_profile_msg profile_id
      end
    end

    def self.get_profiles_from_page(properties, tag, proxy = nil)
      result = {
        success: true,
        properties: nil,
        profile_ids: []
      }
      response = YIParser::HttpClient.get_search_result_accounts SEARCH_TYPE, tag, properties, proxy
      if response[:error]
        return result if response[:error] == 'Finish'

        result[:success] = false
        result[:error] = response[:error]
        return result
      end

      result[:profile_ids] = response[:users]
      result[:properties] = response[:properties]
      result
    end

    def self.send_profile_msg(author_id)
      logger.debug "send id: #{author_id}"
      msg_info = {
        youtube_userid: author_id.strip
      }
      O14::RMQ.send_message @profile_exchange, msg_info
    end

    def self.send_hashtag_msg(hashtag, source, properties, page_number)
      logger.debug "send tag #{hashtag} page_number #{page_number}"
      msg_info = {
        hashtag: hashtag,
        properties: properties,
        page_number: page_number,
        source: source
      }
      O14::RMQ.send_message @hashtags_exchange, msg_info
    end
  end
end
