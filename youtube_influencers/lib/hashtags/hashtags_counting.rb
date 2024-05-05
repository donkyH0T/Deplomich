module YIParser
  class HashtagsCounting
    @config = O14::Config.get_config
    @redis = O14::RDS.instance
    @logger = O14::ProjectLogger.get_logger

    LAST_IMPORT_ID_KEY = @config.infrastructure['redis_keys']['hashtags_last_import_id_key']
    LIMIT_INFLUENCERS_ROWS = 100
    
    def self.db
		O14::DB.get_db
	end

    def self.run
      @logger.debug "Start import"
      db = O14::DB.get_db
      loop do
        last_processed_id = get_last_processed_id
        prev_last_processed_id = last_processed_id
          influencers = db[:youtubeinfluencers].select(:id, :hashtags, :country).where(Sequel.lit('id > ?', last_processed_id)).order(:id).limit(LIMIT_INFLUENCERS_ROWS).all
        influencers.each do |row|
            last_processed_id = row[:id]
            next if row[:hashtags].nil?
            if row[:country] == 'United States'
              process_row row
            end
        end
        @logger.debug("last_processed_id #{last_processed_id}")
        @logger.debug("#{LIMIT_INFLUENCERS_ROWS} rows processed")
        @redis.set(LAST_IMPORT_ID_KEY, last_processed_id)
        if prev_last_processed_id == last_processed_id
	        @logger.debug('No new record. leep 5 min')
	        sleep 60*5
	    end
      end
    end

    def self.process_row row
      hashtags = row[:hashtags].split(/\p{Z}|,\p{Z}|#/)
      hashtags.each do |hashtag|
	    hashtag = '' if hashtag.nil?
	    hashtag = hashtag.gsub(/\[|\]|#|,|"|'/,'').gsub(/\A\p{Z}*|\p{Z}*\z/, '').downcase
        unless hashtag.empty?
	      if hashtag =~ /^[a-zA-Z0-9\-_]+$/ and hashtag.length <= 20
            hashtag_row = db[:hashtags].where(title: hashtag).first
            if hashtag_row.nil?
	          begin
                db[:hashtags].insert(title: hashtag, hashtag_count: 1)
              rescue => e
                if e.message =~ /Cannot insert duplicate key/
	              @logger.warn "Duplicate hashtag #{hashtag}"
	            else
	              raise e
	            end    
              end
            else
              count = hashtag_row[:hashtag_count] + 1
              db[:hashtags].where(title: hashtag).update(hashtag_count: count)
            end
          end
        end
      end
    end

    def self.get_last_processed_id
      last_processed_id = @redis.get(LAST_IMPORT_ID_KEY)
      if last_processed_id.nil?
        last_processed_id = -1
      end
      return last_processed_id.to_i
    end

    def self.clear_redis_hash
      @redis.del LAST_IMPORT_ID_KEY
    end

  end
end