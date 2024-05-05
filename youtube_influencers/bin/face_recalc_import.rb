#!/usr/bin/env ruby
$:.unshift(File.expand_path('../lib', __dir__))

require 'o14/o14'
require 'y_i_parser'
require 'date'
require 'json'


    MESSAGE_LIMIT_IN_QUEUE = 500
    LAST_IMPORT_ID_KEY = 'youtube_face_recalc_last_id'
    INPUT_EXCHANGE_NAME = O14::Config.get_config.infrastructure['face_exchange']
    INPUT_QUEUE_NAME = O14::Config.get_config.infrastructure['face_queue']

    @config = O14::Config.get_config
    @profile_exchange = O14::RMQ.get_channel.direct(INPUT_EXCHANGE_NAME, durable: true)
    @profile_queue = O14::RMQ.get_channel.queue(INPUT_QUEUE_NAME, durable: true)
    
    def self.send_profile_msg(user_id, profile_pic_url_hd)
      msg = {
        'user_id' => user_id,
        'profile_pic_url_hd' => profile_pic_url_hd
      }
      O14::RMQ.send_message(@profile_exchange, msg)
    end

    def self.clear_redis_hash
      @redis.del LAST_IMPORT_ID_KEY
    end
    
def logger
  O14::ProjectLogger.get_logger 'INFO'
end

logger.info 'Face recalc is started'
while true
    message_count = @profile_queue.message_count
    logger.debug "messages in queue = #{message_count}"
    if message_count >= MESSAGE_LIMIT_IN_QUEUE
      logger.debug "sleeping 10 sec"
      sleep 10
      next
    end
    import_count = MESSAGE_LIMIT_IN_QUEUE - message_count
    logger.info "need import #{import_count} messages"

    last_processed_id = -1

    all_influencers = O14::DB.get_db["SELECT id, userid, profilepicture FROM youtubeinfluencers
      WHERE followers >= 1000 and is_face_recalculated = false order by id limit #{import_count};"].all
    logger.info("all_influencers count = #{all_influencers.count}")

    if  all_influencers.count == 0
      logger.info "no influencers for processing, exit"
      sleep 20
      return true
    end
    all_influencers.each do |infl|
	  if infl[:is_face_recalculated].nil? || infl[:is_face_recalculated] == false
        send_profile_msg(infl[:userid], infl[:profilepicture])
      end
      last_processed_id = infl[:id]
    end
    logger.info "last_processed_id #{last_processed_id}"
    O14::DB.get_db[:youtubeinfluencers].where(:id => all_influencers.map{|_e| _e[:id]}).update(:is_face_recalculated => true)
    sleep 20
end