# frozen_string_literal: true

require 'English'
require 'json'
require 'mechanize'
require 'oj'

module YIParser
  class LinktreeHttpClient
    MAIN_URL = 'https://linktr.ee/'

    def self.logger
      O14::ProjectLogger.get_logger
    end

    def self.get_matched_data(body)
      matched = body.match(%r{type="application/json" crossorigin="anonymous">(.+?)</script>})
      if matched.nil?
        matched = body.match(%r{window._prefillApolloCache = {\s*publicProfile:\s*(\{.*?})\s*</script>}m)
        str_json = matched[1].gsub("\n", '').gsub(/\s+/, ' ').chop
      else
        str_json = matched[1]
      end
      str_json.force_encoding(Encoding::UTF_8)
      Oj.default_options = { allow_invalid_unicode: true }
      Oj.load(str_json)
    end

    def self.get_profile_data(nickname, proxy_row = nil)
      agent = Mechanize.new
      if proxy_row
        proxy_server = proxy_row.split(':')
        agent.set_proxy(proxy_server[0], proxy_server[1], proxy_server[2], proxy_server[3])
      end
      url = "#{MAIN_URL}#{nickname}"
      logger.debug url.to_s
      response = nil
      begin
        Timeout.timeout(30) do
          request_time_start = Time.now
          response = agent.get(url, [], MAIN_URL)
          logger.debug("Response time: #{Time.now - request_time_start} sec")
        end
      rescue Net::ReadTimeout
        return { error: 'Ban', mesage: 'ReadTimeout' }
      rescue Timeout::Error
        return { error: 'Ban', mesage: 'Timeout::Error' }
      rescue Mechanize::ResponseCodeError => e
        return { error: 'Page not found', message: 'Page not found' } if $ERROR_INFO.message.match(/Net::HTTPNotFound/)
        return { error: 'Ban', mesage: 'Net::HTTPForbidden' } if $ERROR_INFO.message.match(/Net::HTTPForbidden/)

        raise e
      end
      get_matched_data(response.body)
    end
  end
end
