# frozen_string_literal: true

require 'net/http'
require 'time'

module YIParser
  class ProxiesManager
    USAGE_PERIOD_SEC = 10
    TAGS_USAGE_PERIOD_SEC = 5
    VIDEO_USAGE_PERIOD_SEC = 5
    IPV6_USAGE_PERIOD_SEC = 60
    BM_USAGE_PERIOD_SEC = 60
    @http = HttpClient

    def self.logger
      O14::ProjectLogger.get_logger
    end

    def self.check_proxies
      logger.info 'Start proxies check'
      proxies = O14::DB.get_db[:proxies].all
      logger.info "#{proxies.count} proxies in db"
      while proxies.count.positive?
        accounts_threads = proxies.shift 10
        threads = []
        logger.info "#{proxies.count} left to check"
        accounts_threads.each do |account_row|
          threads << Thread.new(account_row) do |proxy_row|
            seconds = 0
            is_success = false
            begin
              start_t = Time.now
              resp = @http.get_yt_init_data(URI('https://www.youtube.com/watch?v=LGXf5a0KUcM'),
                                            proxy_row[:address])
              if resp && resp != false
                is_success = true
                seconds = (Time.now - start_t).round(0)
              end
            rescue Net::HTTPServerException
            rescue StandardError => e
              O14::ExceptionHandler.log_exception e
            end
            if is_success == false
              logger.info "#{proxy_row[:address]} is bad"
              O14::DB.get_db[:proxies].where(id: proxy_row[:id]).update(is_work: 0, response_time_sec: seconds)
            else
              O14::DB.get_db[:proxies].where(id: proxy_row[:id]).update(is_work: 1, response_time_sec: seconds)
            end
          end
        end
        threads.each(&:join)
      end
    end

    def self.run_periodic_check
      check_proxies
      logger.info 'Check is complete. Sleeping 1 hour...'
      sleep 60 * 60
    end

    def self.get_free_hashtags_proxy
      proxy_address = nil
      O14::DB.get_db.transaction do
        proxy_row = O14::DB.get_db["SELECT *
			FROM proxies
			WHERE tags_last_try_time IS NULL
			LIMIT 1
			FOR UPDATE SKIP LOCKED;"].first
        if proxy_row.nil?
          proxy_row = O14::DB.get_db["SELECT *
			FROM proxies
			WHERE tags_last_try_time <= ?
			ORDER BY tags_last_try_time
			LIMIT 1
			FOR UPDATE SKIP LOCKED;", Time.now - TAGS_USAGE_PERIOD_SEC].first
        end
        if proxy_row
          O14::DB.get_db[:proxies].where(id: proxy_row[:id]).update(tags_last_try_time: Time.now)
          proxy_address = proxy_row[:address]
        end
      end
      proxy_address
    end

    def self.get_free_video_proxy
      proxy_address = nil
      O14::DB.get_db.transaction do
        proxy_row = O14::DB.get_db["SELECT *
			FROM proxies
			WHERE video_last_try_time IS NULL
			LIMIT 1
			FOR UPDATE SKIP LOCKED;"].first
        if proxy_row.nil?
          proxy_row = O14::DB.get_db["SELECT *
			FROM proxies
			WHERE video_last_try_time <= ?
			ORDER BY video_last_try_time
			LIMIT 1
			FOR UPDATE SKIP LOCKED;", Time.now - VIDEO_USAGE_PERIOD_SEC].first
        end
        if proxy_row
          O14::DB.get_db[:proxies].where(id: proxy_row[:id]).update(video_last_try_time: Time.now)
          proxy_address = proxy_row[:address]
        end
      end
      proxy_address
    end

    def self.get_free_bm_proxy
      proxy_address = nil
      O14::DB.get_db.transaction do
        proxy_row = O14::DB.get_db["SELECT *
			FROM proxies
			WHERE bm_last_try_time IS NULL
			LIMIT 1
			FOR UPDATE SKIP LOCKED;"].first
        if proxy_row.nil?
          proxy_row = O14::DB.get_db["SELECT *
			FROM proxies
			WHERE bm_last_try_time <= ?
			ORDER BY bm_last_try_time
			LIMIT 1
			FOR UPDATE SKIP LOCKED;", Time.now - BM_USAGE_PERIOD_SEC].first
        end
        if proxy_row
          O14::DB.get_db[:proxies].where(id: proxy_row[:id]).update(bm_last_try_time: Time.now)
          proxy_address = proxy_row[:address]
        end
      end
      proxy_address
    end

    def self.set_bm_success_usage(proxy_address)
      O14::DB.get_db[:proxies].where(address: proxy_address).update(bm_last_success: Time.now)
    end

    def self.get_free_proxy(_settings = {})
      proxy_address = nil
      O14::DB.get_db.transaction do
        proxy_row = O14::DB.get_db["SELECT *
			FROM proxies
			WHERE last_try_time IS NULL
			LIMIT 1
			FOR UPDATE SKIP LOCKED;"].first
        if proxy_row.nil?
          proxy_row = O14::DB.get_db["SELECT *
			FROM proxies
			WHERE last_try_time <= ?
			ORDER BY last_try_time
			LIMIT 1
			FOR UPDATE SKIP LOCKED;", Time.now - USAGE_PERIOD_SEC].first
        end
        if proxy_row
          O14::DB.get_db[:proxies].where(id: proxy_row[:id]).update(last_try_time: Time.now)
          proxy_address = proxy_row[:address]
        end
      end
      proxy_address
    end

    def self.get_random_proxy(type = nil)
      proxy_row = nil
      O14::DB.get_db.transaction do
        query = O14::DB.get_db[:proxies].where(is_work: 1).order(:last_try_time)
        query = query.where(type: type) if type
        proxy_row = query.first
      end
      return unless proxy_row

      proxy_row[:address]
    end
  end
end
