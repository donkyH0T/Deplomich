module YIParser
  class HashtagsQueueFiller
    @config = O14::Config.get_config

    @hashtags_gueue = O14::RMQ.get_channel.queue(@config.infrastructure['hashtag_import_queue'], durable: true)
    @hashtags_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['hashtag_import_exchange'], durable: true)

    MESSAGE_LIMIT_IN_QUEUE = 500
    
    def self.logger
        O14::ProjectLogger.get_logger
    end
    
    def self.db
        O14::DB.get_db
    end

    def self.run(source)
		logger.debug "Start agent"
			@hashtags_table_name = 'hashtags'
	  	need_process_count = db[@hashtags_table_name.to_sym].where(:is_imported => false).count
	  	
		logger.info "Hashtags need to import: #{need_process_count}"
		while need_process_count > 0
			message_count = @hashtags_gueue.message_count
			need_import_count = MESSAGE_LIMIT_IN_QUEUE - message_count
			if need_import_count > 0
				logger.info "import rows: #{need_import_count}"
				need_import_rows = get_hashtags need_import_count
				update_ids = []
		    	need_import_rows.each do |row|
			    	update_ids.push(row[:id])
                    send_hashtag_msg(row[:title], source)
                end
                if update_ids.count > 0
                    db[@hashtags_table_name.to_sym].where(:id => update_ids).update(:is_imported => true)
                end
                need_process_count = db[@hashtags_table_name.to_sym].where(:is_imported => false).count
                logger.info "Hashtags need to import: #{need_process_count}"
			end
			sleep 10
        end
        if source.nil? || source != 'handmade'
	        db[@hashtags_table_name.to_sym].update(:is_imported => false)
	        logger.info "Set is_imported filed to 0 for all rows"
	    else
	    	logger.info "handmadehashtags processing is finished"
	    	sleep 10
	    end
    end
    
    def self.get_hashtags count
	    all_rows = []
		all_ids = db["SELECT h.id FROM #{@hashtags_table_name} as h WHERE h.is_imported = false ORDER BY hashtag_count DESC LIMIT #{count};"].all.map{|_e| _e[:id]}
		if all_ids.count > 0
			all_rows = db["SELECT h.id, h.title FROM #{@hashtags_table_name} as h
			WHERE h.id IN (#{all_ids.join(',')});"].all
		end
		all_rows
	end
    

    def self.send_hashtag_msg current_tag, source
      logger.debug "send tag #{current_tag}"
      msg_info = {
        hashtag: current_tag,
        page_number: 1,
        source: source
      }
      O14::RMQ.send_message @hashtags_exchange, msg_info
    end

  end
end