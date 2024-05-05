# frozen_string_literal: true

require 'net/http'
require 'zlib'
require 'stringio'
require 'base64'
require 'oj'
require 'addressable/uri'
require 'mechanize'
require 'json'

module YIParser
  class HttpClient
    GET_SEARCH_URL = 'https://www.youtube.com/results?'
    POST_SEARCH_URL = 'https://www.youtube.com/youtubei/v1/search?'
    POST_ACCOUNTS_SEARCH_URL = 'https://www.youtube.com/youtubei/v1/search?'

    def self.logger
      O14::ProjectLogger.get_logger
    end

    def self.get_http
      http = Net::HTTP.new('www.youtube.com', 443)
      http.use_ssl = true
      http
    end

    def self.get_header
      {
        'accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
        'accept-encoding' => 'gzip',
        'accept-language' => 'en-GB,en;q=0.9,en-US;q=0.8,ru;q=0.7',
        'cache-control' => 'no-cache',
        'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.4951.64 Safari/537.36'
      }
    end
    def self.execute_get_with_proxy(url, headers = nil)
      uri = URI(url)
      headers = get_header if headers.nil?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      http.start do |h|
        request = Net::HTTP::Get.new(uri)
        headers.each { |key, value| request[key] = value }
        h.request(request)
      end
    end

    def self.get_yt_init_data(url)
      response = execute_get_with_proxy url
      uncompressed_string = nil
      sss = response.body.to_s

      if sss.match(/The document has moved/) || sss.match(%r{<title>404 Not Found</title>})
        logger.debug('404 case 1')
        return false
      end
      if response.code == '303' && response['location']
        response = execute_get_with_proxy response['location']
        sss = response.body.to_s
        if sss.match(/The document has moved/) || sss.match(%r{<title>404 Not Found</title>})
          logger.debug('404 case 2')
          return nil
        end
      end
      begin
        gz = Zlib::GzipReader.new(StringIO.new(sss))
        uncompressed_string = gz.read
      rescue StandardError => e
        O14::ExceptionHandler.log_exception e
        logger.error sss
        logger.error response.to_hash
        return false
      end
      matched = uncompressed_string.match(%r{var ytInitialData = (.+?);</script>})
      if matched && matched[1]
        str_json = matched[1]
      else
        if uncompressed_string.match(%r{<title>404 Not Found</title>})
          logger.debug('404 case 3')
          return nil
        end
        return false
      end
      Oj.load(str_json)
    end

    def self.get_search_result_accounts(search_type, tag, query_parameters, proxy_row = nil)
      unless %w[videos channels location].include? search_type
        return { error: "incorrect search_type parameter '#{search_type}' in the get_search_result_accounts method" }
      end

      query_param_sp = ''
      use_followers_count_filter = false
      case search_type
      when 'videos'
        query_param_sp = 'CAMSBAgEEAE%3D'
      when 'channels'
        query_param_sp = 'EgIQAg'
        use_followers_count_filter = true
      when 'location'
        query_param_sp = 'EgO4AQE%3D'
      end

      agent = Mechanize.new
      remote_host = '3.237.236.88'
      if proxy_row
        proxy_server = proxy_row.split(':')
        agent.set_proxy(proxy_server[0], proxy_server[1], proxy_server[2], proxy_server[3])
        remote_host = proxy_server[0]
      end

      api_key = nil
      uri = Addressable::URI.new
      if query_parameters && query_parameters[:key] && query_parameters[:continuation]
        api_key = query_parameters[:key]
        uri.query_values = {
          key: api_key,
          prettyPrint: false
        }
        json_str = "{\"context\":{\"client\":{\"hl\":\"en\",\"gl\":\"US\",\"remoteHost\":\"#{remote_host}\",\"deviceMake\":\"Apple\",\"deviceModel\":\"\",\"visitorData\":\"CgtFN2hfeFVKSVYwNCi_q_yfBg%3D%3D\",\"userAgent\":\"Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/110.0,gzip(gfe)\",\"clientName\":\"WEB\",\"clientVersion\":\"2.20230221.06.00\",\"osName\":\"Macintosh\",\"osVersion\":\"10.15\",\"originalUrl\":\"https://www.youtube.com/results?search_query=vlog\",\"screenPixelDensity\":2,\"platform\":\"DESKTOP\",\"clientFormFactor\":\"UNKNOWN_FORM_FACTOR\",\"configInfo\":{\"appInstallData\":\"CL-r_J8GELjUrgUQ4tSuBRDloP4SEOyGrwUQh92uBRD-7q4FEOf3rgUQlPiuBRCC3a4FEMzfrgUQieiuBRDa6a4FELis_hIQouyuBRDM9a4FENOs_hIQtpz-EhC4i64FEMnJrgU%3D\"},\"screenDensityFloat\":2,\"timeZone\":\"Europe/Samara\",\"browserName\":\"Firefox\",\"browserVersion\":\"110.0\",\"acceptHeader\":\"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8\",\"deviceExperimentId\":\"ChxOekU1TkRNMU9UVTRNalEyTURBeE56WXhNdz09EL-r_J8GGOz_3Z4G\",\"screenWidthPoints\":1584,\"screenHeightPoints\":942,\"utcOffsetMinutes\":240,\"userInterfaceTheme\":\"USER_INTERFACE_THEME_LIGHT\",\"mainAppWebInfo\":{\"graftUrl\":\"https://www.youtube.com/results?search_query=vlog\",\"webDisplayMode\":\"WEB_DISPLAY_MODE_BROWSER\",\"isWebNativeShareAvailable\":false}},\"user\":{\"lockedSafetyMode\":false},\"request\":{\"useSsl\":true,\"internalExperimentFlags\":[],\"consistencyTokenJars\":[]},\"clickTracking\":{\"clickTrackingParams\":\"CBoQui8iEwiL6v_MsLr9AhWGwD8EHfcWAOg=\"},\"adSignalsInfo\":{\"params\":[{\"key\":\"dt\",\"value\":\"1677661633168\"},{\"key\":\"flash\",\"value\":\"0\"},{\"key\":\"frm\",\"value\":\"0\"},{\"key\":\"u_tz\",\"value\":\"240\"},{\"key\":\"u_his\",\"value\":\"3\"},{\"key\":\"u_h\",\"value\":\"1080\"},{\"key\":\"u_w\",\"value\":\"1920\"},{\"key\":\"u_ah\",\"value\":\"1055\"},{\"key\":\"u_aw\",\"value\":\"1920\"},{\"key\":\"u_cd\",\"value\":\"30\"},{\"key\":\"bc\",\"value\":\"31\"},{\"key\":\"bih\",\"value\":\"942\"},{\"key\":\"biw\",\"value\":\"1584\"},{\"key\":\"brdim\",\"value\":\"0,25,0,25,1920,25,1584,1055,1584,942\"},{\"key\":\"vis\",\"value\":\"1\"},{\"key\":\"wgl\",\"value\":\"true\"},{\"key\":\"ca_type\",\"value\":\"image\"}]}},\"continuation\":\"#{query_parameters[:continuation]}\"}"
        url = POST_SEARCH_URL + uri.query
        logger.debug("url: #{url}")
        response = agent.post(url, json_str, { 'Content-Type' => 'application/json' })
        init_data = JSON.parse(response.body)
      else
        uri.query_values = {
          search_query: tag,
          sp: query_param_sp
        }
        url = GET_SEARCH_URL + uri.query
        logger.debug("url: #{url}")
        response = agent.get(url)
        content = response.body
        matched = content.match(/"INNERTUBE_API_KEY":"(.+?)"/)
        api_key = matched[1] if matched && matched[1]
        matched = content.match(%r{var ytInitialData = (.+?);</script>})
        if matched && matched[1]
          str_json = matched[1]
          init_data = Oj.load(str_json)
        end
      end
      continuation = get_continuation(init_data)
      users = get_users(init_data, use_followers_count_filter)

      {
        properties: {
          key: api_key,
          continuation: continuation
        },
        users: users
      }
    end

    def self.get_search_results(tag, query_parameters, proxy_row = nil)
      agent = Mechanize.new
      remote_host = '3.237.236.88'
      if proxy_row
        proxy_server = proxy_row.split(':')
        agent.set_proxy(proxy_server[0], proxy_server[1], proxy_server[2], proxy_server[3])
        remote_host = proxy_server[0]
      end

      api_key = nil
      uri = Addressable::URI.new
      if query_parameters && query_parameters[:key] && query_parameters[:continuation]
        api_key = query_parameters[:key]
        uri.query_values = {
          key: api_key,
          prettyPrint: false
        }
        json_str = "{\"context\":{\"client\":{\"hl\":\"en\",\"gl\":\"US\",\"remoteHost\":\"#{remote_host}\",\"deviceMake\":\"Apple\",\"deviceModel\":\"\",\"visitorData\":\"CgtFN2hfeFVKSVYwNCi_q_yfBg%3D%3D\",\"userAgent\":\"Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/110.0,gzip(gfe)\",\"clientName\":\"WEB\",\"clientVersion\":\"2.20230221.06.00\",\"osName\":\"Macintosh\",\"osVersion\":\"10.15\",\"originalUrl\":\"https://www.youtube.com/results?search_query=vlog\",\"screenPixelDensity\":2,\"platform\":\"DESKTOP\",\"clientFormFactor\":\"UNKNOWN_FORM_FACTOR\",\"configInfo\":{\"appInstallData\":\"CL-r_J8GELjUrgUQ4tSuBRDloP4SEOyGrwUQh92uBRD-7q4FEOf3rgUQlPiuBRCC3a4FEMzfrgUQieiuBRDa6a4FELis_hIQouyuBRDM9a4FENOs_hIQtpz-EhC4i64FEMnJrgU%3D\"},\"screenDensityFloat\":2,\"timeZone\":\"Europe/Samara\",\"browserName\":\"Firefox\",\"browserVersion\":\"110.0\",\"acceptHeader\":\"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8\",\"deviceExperimentId\":\"ChxOekU1TkRNMU9UVTRNalEyTURBeE56WXhNdz09EL-r_J8GGOz_3Z4G\",\"screenWidthPoints\":1584,\"screenHeightPoints\":942,\"utcOffsetMinutes\":240,\"userInterfaceTheme\":\"USER_INTERFACE_THEME_LIGHT\",\"mainAppWebInfo\":{\"graftUrl\":\"https://www.youtube.com/results?search_query=vlog\",\"webDisplayMode\":\"WEB_DISPLAY_MODE_BROWSER\",\"isWebNativeShareAvailable\":false}},\"user\":{\"lockedSafetyMode\":false},\"request\":{\"useSsl\":true,\"internalExperimentFlags\":[],\"consistencyTokenJars\":[]},\"clickTracking\":{\"clickTrackingParams\":\"CBoQui8iEwiL6v_MsLr9AhWGwD8EHfcWAOg=\"},\"adSignalsInfo\":{\"params\":[{\"key\":\"dt\",\"value\":\"1677661633168\"},{\"key\":\"flash\",\"value\":\"0\"},{\"key\":\"frm\",\"value\":\"0\"},{\"key\":\"u_tz\",\"value\":\"240\"},{\"key\":\"u_his\",\"value\":\"3\"},{\"key\":\"u_h\",\"value\":\"1080\"},{\"key\":\"u_w\",\"value\":\"1920\"},{\"key\":\"u_ah\",\"value\":\"1055\"},{\"key\":\"u_aw\",\"value\":\"1920\"},{\"key\":\"u_cd\",\"value\":\"30\"},{\"key\":\"bc\",\"value\":\"31\"},{\"key\":\"bih\",\"value\":\"942\"},{\"key\":\"biw\",\"value\":\"1584\"},{\"key\":\"brdim\",\"value\":\"0,25,0,25,1920,25,1584,1055,1584,942\"},{\"key\":\"vis\",\"value\":\"1\"},{\"key\":\"wgl\",\"value\":\"true\"},{\"key\":\"ca_type\",\"value\":\"image\"}]}},\"continuation\":\"#{query_parameters[:continuation]}\"}"
        url = POST_SEARCH_URL + uri.query
        logger.debug("url: #{url}")
        response = agent.post(url, json_str, { 'Content-Type' => 'application/json' })
        init_data = JSON.parse(response.body)
      else
        uri.query_values = {
          search_query: tag,
          sp: 'CAMSBAgEEAE%3D'
        }
        url = GET_SEARCH_URL + uri.query
        logger.debug("url: #{url}")
        response = agent.get(url)
        content = response.body
        matched = content.match(/"INNERTUBE_API_KEY":"(.+?)"/)
        api_key = matched[1] if matched && matched[1]
        matched = content.match(%r{var ytInitialData = (.+?);</script>})
        if matched && matched[1]
          str_json = matched[1]
          init_data = Oj.load(str_json)
        end
      end
      continuation = get_continuation(init_data)
      users = get_users(init_data)

      {
        properties: {
          key: api_key,
          continuation: continuation
        },
        users: users
      }
    end

    def self.get_continuation(json_content)
      continuation = nil
      if json_content['contents']
        contents = json_content['contents']['twoColumnSearchResultsRenderer']['primaryContents']['sectionListRenderer']['contents']
        contents.each do |content|
          continuation = get_continuation_token content
        end
      elsif json_content['onResponseReceivedCommands']
        json_content['onResponseReceivedCommands'].each do |command|
          unless command['appendContinuationItemsAction'] && command['appendContinuationItemsAction']['continuationItems']
            next
          end

          command['appendContinuationItemsAction']['continuationItems'].each do |content|
            continuation = get_continuation_token content
          end
        end
      end
      continuation
    end

    def self.get_continuation_token(content)
      if content['continuationItemRenderer'] && content['continuationItemRenderer']['continuationEndpoint'] && content['continuationItemRenderer']['continuationEndpoint']['continuationCommand']
        return content['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token']
      end

      nil
    end

    def self.get_videos(content); end

    def self.get_users(json_content, with_followers_count = false)
      user_ids = []
      if with_followers_count
        if json_content['onResponseReceivedCommands']
          json_content['onResponseReceivedCommands'].each do |command|
            next unless command['appendContinuationItemsAction']

            command['appendContinuationItemsAction']['continuationItems'].each do |item|
              next unless item['itemSectionRenderer'] && item['itemSectionRenderer']['contents']

              item['itemSectionRenderer']['contents'].each do |content|
                next unless content['channelRenderer'] && !content['channelRenderer']['videoCountText'].nil?

                subscriber_simple_text = if content['channelRenderer']['videoCountText']['simpleText'].nil?
                                           if content['channelRenderer']['subscriberCountText'].nil?
                                             ''
                                           else
                                             content['channelRenderer']['subscriberCountText']['simpleText']
                                           end
                                         else
                                           content['channelRenderer']['videoCountText']['simpleText']
                                         end
                followers_count = process_subscribers_count(subscriber_simple_text)
                user_ids.push(content['channelRenderer']['channelId']) if followers_count >= 1000
              end
            end
          end
        elsif json_content['contents']
          json_content['contents']['twoColumnSearchResultsRenderer']['primaryContents']['sectionListRenderer']['contents'].each do |content|
            next unless content['itemSectionRenderer']

            content['itemSectionRenderer']['contents'].each do |content2|
              next unless content2['channelRenderer'] && !content2['channelRenderer']['videoCountText'].nil?

              subscriber_simple_text = if content2['channelRenderer']['videoCountText']['simpleText'].nil?
                                         if content2['channelRenderer']['subscriberCountText'].nil?
                                           ''
                                         else
                                           content2['channelRenderer']['subscriberCountText']['simpleText']
                                         end
                                       else
                                         content2['channelRenderer']['videoCountText']['simpleText']
                                       end
              followers_count = process_subscribers_count(subscriber_simple_text)
              user_ids.push(content2['channelRenderer']['channelId']) if followers_count >= 1000
            end
          end
        end
        user_ids.uniq
      else
        user_ids = json_content.to_json.scan(/"browseId":"(.+?)"/).map(&:first).reject do |e|
          e == 'FEwhat_to_watch'
        end.uniq
      end
      user_ids
    end

    def self.process_subscribers_count(subscriber_simple_text)
      subscriber_count_text = subscriber_simple_text.gsub(' subscribers', '')
      subscriber_count = subscriber_count_text.to_f
      subscriber_count = (subscriber_count * 1000.0).round if subscriber_count_text.match(/K/)
      subscriber_count = (subscriber_count * 1_000_000.0).round if subscriber_count_text.match(/M/)
      subscriber_count = (subscriber_count * 1_000_000_000.0).round if subscriber_count_text.match(/B/)
      subscriber_count.to_i
    end
  end
end
