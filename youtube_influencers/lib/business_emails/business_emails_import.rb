module YIParser
  class BusinessEmailsImport
    MESSAGE_LIMIT_IN_QUEUE = 100
    SLEEP_TIME = 10
    TABLE_NAME = 'youtubeinfluencers'
    FILE_PATH = "#{__dir__}/../../tmp/last_import_id_key.txt"

    @business_email_channels_exchange = O14::RMQ.get_channel.direct(
      O14::Config.get_config.infrastructure['business_email_channels_exchange'], durable: true
    )
    @business_email_channels_queue = O14::RMQ.get_channel.queue(
      O14::Config.get_config.infrastructure['business_email_channels_queue'], durable: true
    )

    def self.run
      loop do
        message_count = @business_email_channels_queue.message_count
        import_count = MESSAGE_LIMIT_IN_QUEUE - message_count
        if import_count.positive?
          last_processed_id = get_last_processed_id
          logger.debug("Last processed id is #{last_processed_id}")
          db[TABLE_NAME.to_sym].select(:id, :userid,
                                       :email).where(Sequel.lit('id > ?',
                                                                last_processed_id)).order(:id).limit(import_count).each do |row|
            last_processed_id = row[:id]
            next if row[:email] && !row[:email].empty?

            send_queue_msg(row)
          end
          logger.debug("Add #{import_count} msg in queue")
          File.open(FILE_PATH, 'w') do |file|
            file.puts last_processed_id
          end
        else
          sleep(SLEEP_TIME)
        end
      end
    end

    def self.get_last_processed_id
      last_processed_id = if File.exist?(FILE_PATH)
                            File.open(FILE_PATH).read.to_i
                          else
                            -1
                          end
      last_processed_id.to_i
    end

    def self.send_queue_msg(row)
      msg_info = {
        id: row[:id],
        userid: row[:userid]
      }
      O14::RMQ.send_message(@business_email_channels_exchange, msg_info)
    end

    def self.db
      O14::DB.get_db
    end

    def self.logger
      O14::ProjectLogger.get_logger
    end
  end
end
