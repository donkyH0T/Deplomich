require 'date'
require 'json'


module YIParser
  class UpdateInfluencersFiller
    MESSAGE_LIMIT_IN_QUEUE = 500
    INPUT_EXCHANGE_NAME = O14::Config.get_config.infrastructure['import_exchange']
    INPUT_QUEUE_NAME = O14::Config.get_config.infrastructure['import_queue']

    @config = O14::Config.get_config
    @profile_exchange = O14::RMQ.get_channel.direct(INPUT_EXCHANGE_NAME, durable: true)
    @profile_queue = O14::RMQ.get_channel.queue(INPUT_QUEUE_NAME, durable: true)



    def self.run
      logger.info 'update inluencers filler is started'
      while true
        message_count = @profile_queue.message_count
        logger.debug "messages in queue = #{message_count}"
        if message_count >= MESSAGE_LIMIT_IN_QUEUE
          logger.debug "sleeping 10 sec"
          sleep 10
          next
        end

        all_influencers = O14::DB.get_db["SELECT id, userid
                             FROM youtubeinfluencers
                             WHERE updatedat < current_date - interval '1 month'
                               AND followers >= 1000
                               AND is_updated = FALSE
                             ORDER BY updatedat
                             LIMIT 100;"].all
        logger.info("all_influencers count = #{all_influencers.count}")

        if  all_influencers.count == 0
          logger.info "no influencers for processing"
          sleep 20
          next
        end
        all_influencers.each do |infl|
          send_profile_msg(infl[:userid])
        end
        O14::DB.get_db[:youtubeinfluencers].where(:id => all_influencers.map{|_e| _e[:id]}).update(:is_updated => true)
        sleep 100
      end
    end

    def self.send_profile_msg(user_id)
      msg_info = {
        youtube_userid: user_id.strip
      }
      O14::RMQ.send_message(@profile_exchange, msg_info)
    end

    def self.logger
      O14::ProjectLogger.get_logger
    end

  end
end