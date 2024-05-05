require 'net/http'
require 'zlib'
require 'stringio'
require 'base64'
require 'oj'
require 'cgi'

module YIParser
  class ProfileCrawler
    def self.run
      names = O14::DB.get_db[:InfluencersV2].select(:name).order(:id).limit(10000).all
      O14::ProjectLogger.get_logger.info "#{names.count} names selected from db"
      processed_count = 0
      names.each do |db_row|
        insta_name = db_row[:name].strip
        O14::ProjectLogger.get_logger.info "Name is #{insta_name}"
        nick = get_insta_nick insta_name
        nick = '' if nick.nil?
        O14::ProjectLogger.get_logger.info "Insta nick is #{nick}"
        processed_count += 1
        O14::ProjectLogger.get_logger.info "Processed count = #{processed_count}"
      end
    end

    def self.get_insta_nick insta_name
      # headers = {
      #     'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      #     'Cookie': 'PREF=f4=4000000&tz=Europe.Samara&f6=40000000; GPS=1; VISITOR_INFO1_LIVE=4kZ9aatCrQc; YSC=LrMgummap48',
      #     'Referer': 'https://www.youtube.com/user/deichmannRU',
      #     'Cache-Control': 'max-age=0',
      #     'Host': 'www.youtube.com',
      #     'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15',
      #     'Accept-Language': 'en-us',
      #     'Accept-Encoding': 'gzip',
      #     'Connection': 'keep-alive',
      #     'Cookie': 'GPS=1;PREF=f4=4000000&tz=Europe.Samara&f6=40000000;VISITOR_INFO1_LIVE=4kZ9aatCrQc;YSC=LrMgummap48'
      # }
      headers = {
        'accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
        'accept-encoding' => 'gzip',
        'accept-language' => 'en-GB,en;q=0.9,en-US;q=0.8,ru;q=0.7',
        'cache-control' => 'no-cache',
        'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.4951.64 Safari/537.36'
      }
      http = Net::HTTP.new('www.youtube.com', 443)
      http.use_ssl = true
      insta_name = CGI.escape(insta_name)
      uri = URI("https://www.youtube.com/results?search_query=#{insta_name}")
      O14::ProjectLogger.get_logger.info "#{uri.to_s}"
      response = http.get(uri, headers)
      gz = Zlib::GzipReader.new(StringIO.new(response.body.to_s))
      uncompressed_string = gz.read
      str_json = uncompressed_string.match(/var ytInitialData = (.+?);<\/script>/)[1]
      init_data = Oj.load(str_json)
      channel = init_data['contents']['twoColumnSearchResultsRenderer']['primaryContents']['sectionListRenderer']['contents'][0]['itemSectionRenderer']['contents'][0]['channelRenderer']
      if channel.nil?
        return nil
      end
      chanel_url = channel['navigationEndpoint']['commandMetadata']['webCommandMetadata']['url']
      uri = URI("https://www.youtube.com#{chanel_url}")
      O14::ProjectLogger.get_logger.info "Profile url is #{uri.to_s}"
      response = http.get(uri, headers)
      gz = Zlib::GzipReader.new(StringIO.new(response.body.to_s))
      uncompressed_string = gz.read
      str_json = uncompressed_string.match(/var ytInitialData = (.+?);<\/script>/)[1]
      init_data = Oj.load(str_json)
      if init_data['header'].nil?
        O14::ProjectLogger.get_logger.error 'Content not found'
        return nil
      end
      if init_data['header']['c4TabbedHeaderRenderer'].nil?
        return nil
      end
      header_links = init_data['header']['c4TabbedHeaderRenderer']['headerLinks']
      if header_links.nil?
        return nil
      end
      nick = search_instagram_nickname header_links['channelHeaderLinksRenderer']['primaryLinks']
      if nick.nil?
        nick = search_instagram_nickname header_links['channelHeaderLinksRenderer']['secondaryLinks']
      end
      return nick
    end

    def self.search_instagram_nickname links
      return nil if links.nil?
      links.each do |link|
        if link['title']['simpleText'] == 'Instagram'
          url = link['navigationEndpoint']['commandMetadata']['webCommandMetadata']['url']
          nick = ''
          begin
            nick = url.match(/instagram.com%2F(.+)/)[1].gsub('%2F', '')
            return nick
          rescue
            O14::ProjectLogger.get_logger.error "Not processed insta url. Url is #{url}"
          end
          return
        end
      end
      return nil
    end
  end
end