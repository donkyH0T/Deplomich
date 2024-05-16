# frozen_string_literal: true

module YIParser
  class LocationQueueFiller
    MESSAGE_LIMIT_IN_QUEUE = 300

    @hashtags_gueue = O14::RMQ.get_channel.queue(O14::Config.get_config.infrastructure['hashtag_import_queue'],
                                                 durable: true)
    @hashtags_exchange = O14::RMQ.get_channel.direct(O14::Config.get_config.infrastructure['hashtag_import_exchange'],
                                                     durable: true)

    def self.logger
      O14::ProjectLogger.get_logger
    end

    def self.db
      O14::DB.get_db
    end

    def self.run
      logger.info 'Start agent'
      need_process_count = db[:searched_locations].where(is_imported: false).limit(1).first
      logger.info "Are there any more rows to import: #{!need_process_count.nil?}"
      if !need_process_count.nil?
        message_count = @hashtags_gueue.message_count
        need_import_count = MESSAGE_LIMIT_IN_QUEUE - message_count
        if need_import_count.positive?
          logger.info "import rows: #{need_import_count}"
          need_import_rows = get_locations_ids need_import_count
          update_ids = []
          need_import_rows.each do |row|
            update_ids << row[:id]
            send_city_page_msg(row[:city])
          end
          db[:searched_locations].where(id: update_ids).update(is_imported: true) if update_ids.count.positive?
          need_process_count = db[:searched_locations].where(is_imported: false).limit(1).first
          logger.info "Are there any more rows to import: #{!need_process_count.nil?}"
        end
        sleep 30
      else
        db[:searched_locations].where(is_imported: true).update(is_imported: false)
      end
    end

    def self.get_locations_ids(count)
      all_rows = []
      all_ids = db['SELECT id FROM searched_locations WHERE country = ? AND is_imported = false LIMIT ?;',
                   'United States', count].all.map { |_e| _e[:id] }
      if all_ids.count.positive?
        all_rows = db['SELECT id, city FROM searched_locations
        WHERE id IN ?;', all_ids].all
      end
      all_rows
    end

    def self.send_city_page_msg(city)
      logger.debug "send city #{city}"
      msg_info = {
        hashtag: city,
        page_number: 1,
        source: 'locations'
      }
      O14::RMQ.send_message @hashtags_exchange, msg_info
    end
  end
end
