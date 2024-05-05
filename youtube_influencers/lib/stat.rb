# frozen_string_literal: true

require 'net/http'
require 'zlib'
require 'stringio'
require 'json'
require 'time'
require 'date'

module YIParser
  class Stat
    @config = O14::Config.get_config

    #Tables
    INFLUENCERS_TABLE = 'YouTubeInfluencers' #@config.settings['export_parent_table_name']
    PROXIES_TABLE = 'Proxies'

    def self.run()
      @logger = O14::ProjectLogger.get_logger
      all_influencers_count = 0
      #all_video_count = 0
      current_time = Time.now.utc
      (0..5).to_a.reverse.each do |day_number|
        common_query = "select COUNT(*) as cnt from #{INFLUENCERS_TABLE} where followers >= 1000 AND createdat > '#{(current_time - 60 * 60 * 24 * day_number).strftime("%Y-%m-%d")} 00:00:00.0000000' AND createdat < '#{(current_time - 60 * 60 * 24 * (day_number - 1)).strftime("%Y-%m-%d")} 00:00:00.0000000'"
        influencers_count = O14::DB.get_db[common_query].first[:cnt] rescue 0
        us_influencers_count = O14::DB.get_db[common_query.gsub('where', 'where country = \'United States\' AND ')].first[:cnt] rescue 0
        emails_influencers_count = O14::DB.get_db[common_query.gsub('where', 'where email IS NOT NULL AND ')].first[:cnt] rescue 0
        if influencers_count == 0
	      us_percent = 0
	    else
          us_percent = (us_influencers_count.to_f/influencers_count.to_f * 100.0).round(0)
        end
        @logger.info "#{(current_time - 60 * 60 * 24 * day_number).strftime("%Y-%m-%d")} - influencers count = #{influencers_count}, US #{us_percent}%, emails = #{emails_influencers_count}"
        all_influencers_count += influencers_count
      end
      hour_ago = Time.now - 60*60
      last_hour_query = "SELECT COUNT(id) as cnt FROM #{INFLUENCERS_TABLE} WHERE followers >= 1000 AND createdat >= ?;"
      influencers_count = O14::DB.get_db[last_hour_query, hour_ago].first
      us_influencers_count = O14::DB.get_db[last_hour_query.gsub('WHERE', 'WHERE country = \'United States\' AND '), hour_ago].first
      us_percent = 0
      if influencers_count[:cnt] > 0
        us_percent = (us_influencers_count[:cnt].to_f/influencers_count[:cnt].to_f * 100.0).round(0)
      end
      @logger.info "Last hour influencers = #{influencers_count[:cnt]}, US #{us_percent}%"

      proxy_all_count = O14::DB.get_db["select COUNT(*) as cnt from #{PROXIES_TABLE};"].first
      work_proxy_count = O14::DB.get_db["select COUNT(*) as cnt from #{PROXIES_TABLE} where is_work = 'true';"].first
      
      @logger.info "all_influencers_count = #{all_influencers_count}"
      @logger.info "Proxy: #{work_proxy_count[:cnt]}/#{proxy_all_count[:cnt]} work."
    end
  end
end
