module YIParser
  class ProfileImporter

    @config = O14::Config.get_config
    @import_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['import_exchange'], durable: true)
    @import_queue = O14::RMQ.get_channel.queue(@config.infrastructure['import_queue'], durable: true)
    @redis = O14::RDS.instance
    @logger = O14::ProjectLogger.get_logger

    MESSAGE_LIMIT_IN_QUEUE = 2000
    LAST_IMPORT_ID_KEY = @config.infrastructure['redis_keys']['last_import_id_key']
    SLEEP_TIME = 10
    INSTA_TABLE_NAME = 'InstagramInfluencersV3'

    def self.run
# 	  clear_redis_hash
# p @redis.get(LAST_IMPORT_ID_KEY)
# 	  exit
      is_loop = true
      db = O14::DB.create_connection(@config.db2)
      while(is_loop)
        message_count = @import_queue.message_count
        import_count = MESSAGE_LIMIT_IN_QUEUE - message_count
        if import_count > 0
          last_processed_id = get_last_processed_id
          @logger.debug("Last processed id is #{last_processed_id}")
          db[INSTA_TABLE_NAME.to_sym].select(:id, :username, :biography, :influencerid, :userid).where(Sequel.lit('id > ?', last_processed_id)).order(:id).limit(import_count).each do |row|
            last_processed_id = row[:id]
            send_profile_msg row
          end
          @logger.debug("Add #{import_count} msg in queue")
          @redis.set(LAST_IMPORT_ID_KEY, last_processed_id)
        else
          sleep(SLEEP_TIME)
        end
      end
    end

    def self.get_last_processed_id
      last_processed_id = @redis.get(LAST_IMPORT_ID_KEY)
      if last_processed_id.nil?
        last_processed_id = 0
      end
      return last_processed_id.to_i
    end

    def self.send_profile_msg row
      msg_info = {
        username: row[:username].strip,
        biography: row[:biography],
        userid: row[:userid],
        influencer_id: row[:influencerid],
        source_table: INSTA_TABLE_NAME
      }
      O14::RMQ.send_message @import_exchange, msg_info
    end
    
    def self.clear_redis_hash
        @redis.del LAST_IMPORT_ID_KEY
    end
    
    
  end
end