
require 'rest-client'

module YIParser
  class BusinessEmailsAgent
    EXPORT_EXCHANGE_NAME = 'exchange.export'

    @queue = O14::RMQ.get_channel.queue('queue.business_email_channels', durable: true)
    @export_exchange = O14::RMQ.get_channel.direct(EXPORT_EXCHANGE_NAME, durable: true)

    def self.run
      logger.debug('Started')
      @queue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, body|
        proxy = YIParser::ProxiesManager.get_free_bm_proxy
        if proxy.nil?
          O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
          logger.info 'No proxies. Sleeping 10 sec...'
          sleep 10
          next
        end
        logger.info("Proxy #{proxy}")
        proxy_r = proxy.split(':')
        O14::WebBrowser.set_proxy({host: proxy_r[0], port: proxy_r[1]})
        msg = JSON.parse(body, symbolize_names: true)
        logger.info("channel #{msg[:userid]}")
        start_time_load = Time.now
        driver.navigate.to "https://www.youtube.com/channel/#{msg[:userid]}/about"
        logger.debug "Page load by #{Time.now - start_time_load}"
        title_text_el = nil
        error_el = nil
        (1..10).each do
          accept_all_button = driver.find_element(xpath: '//span[contains(text(),"Accept all")]') rescue nil
          accept_all_button.click if accept_all_button
          error_el = driver.find_element(css: '#container.ERROR') rescue nil
          title_text_el = driver.find_element(css: 'ytd-popup-container #title-text') rescue nil
          break if title_text_el || error_el
          sleep 1
        end
        if error_el
          logger.info('Channel has been terminated for violating')
          YIParser::ProxiesManager.set_bm_success_usage(proxy)
          O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
          O14::WebBrowser.quit_browser
          next
        end
        if title_text_el.nil?
          logger.error('Youtube page title not found')
          driver.save_screenshot("screenshots/be_title_not_found.png")
          O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
          O14::WebBrowser.quit_browser
          next
        end
        YIParser::ProxiesManager.set_bm_success_usage(proxy)

        parsed_email_el = driver.find_element(xpath: '//a[contains(text(),"Sign in")]') rescue nil

        if parsed_email_el.nil?
          logger.info('No email element')
          driver.save_screenshot("screenshots/be_email_btn_not_found.png")
          O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
          O14::WebBrowser.quit_browser
          next
        end
        account = get_account
        if account.nil?
          O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
          O14::WebBrowser.quit_browser
          sleep 10
          next
        else
          logger.info "Account id #{account[:id]}"
          begin
            set_cookies(account[:cookies])
          rescue
            logger.error 'Something with browser...'
            logger.error "#{$!.class.name}\n#{$!.message}\n#{$!.backtrace.join("\n")}"
            O14::WebBrowser.quit_browser
            O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
            next
          end
          parse_result = parse_emails
          logger.info(parse_result)
          db[:google_accounts_history].insert(google_acoount_id: account[:id], proxy: proxy_r.join(':'), result: parse_result.to_json, channel_id: msg[:userid])
          if parse_result[:success]
            db[:google_accounts].where(:id => account[:id]).update(:last_login => true, :last_success_login => Time.now)
            msg = {
              type: 'influencer_emails',
              data: {
                youtube_influencer_id: msg[:id],
                emails: [
                  {
                    email: parse_result[:email],
                    source: 'business_email',
                    is_correct: nil
                  }
                ]
              }
            }
            logger.info(msg)
            O14::RMQ.send_message(@export_exchange, msg)
            O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
          else
            if parse_result[:msg] == 'captcha_attempt'
              db[:google_accounts].where(id: account[:id]).update(last_captcha_attempt: Time.now)
            elsif parse_result[:msg] == 'unknown_error'
              driver.save_screenshot("screenshots/be_auth_no_email_btn.png")
            end
            O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
          end
        end
        O14::WebBrowser.quit_browser
      rescue Bunny::Session
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        logger.error "#{Time.now} - Bunny::Session Error"
      rescue => e
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        O14::WebBrowser.quit_browser
        logger.error "#{$!.class.name}\n#{$!.message}\n#{$!.backtrace.join("\n")}"
      end
    end

    private

    def self.db
      O14::DB.get_db
    end

    def self.driver
      O14::WebBrowser.get_driver
    end

    def self.logger
      O14::ProjectLogger.get_logger
    end

    def self.get_account
      account = nil
      db.transaction do
        account = db["SELECT * FROM google_accounts WHERE cookies IS NOT NULL AND cookies != 'Error' AND last_try_time IS NULL"].first
        if account.nil?
          account = db["SELECT * FROM google_accounts WHERE cookies IS NOT NULL AND cookies != 'Error' AND (last_captcha_attempt <= ? OR last_captcha_attempt IS NULL) ORDER BY last_try_time", Time.now - 60*60].first
        end
        if account
          db[:google_accounts].where(:id => account[:id]).update(:last_try_time => Time.now)
        end
      end
      account
    end

    def self.set_cookies(account_cookies_str)
      logger.debug 'Start set_cookies'
      account_cookies = account_cookies_str.scan(/(.*?)=(.*?)($|;|,(?! ))/)

      driver.manage.delete_all_cookies

      account_cookies.each do |value|
        k = value[0].strip
        v = value[1].strip
        is_secure = false
        is_secure = true if k =~ /__Secure/
        cookie = {name: k, value: v, secure: is_secure, domain: 'youtube.com'}
        driver.manage.add_cookie(cookie)
      end

      start_time_load = Time.now
      driver.navigate.refresh
      logger.debug "Page refresh by #{Time.now - start_time_load}"
    end

    def self.parse_emails
      parse_result = {
        success: false,
        email: nil,
        msg: ''
      }

      login_logo = nil
      (1..10).each do
        login_logo = driver.find_element(css: '#masthead img#img') rescue nil
        if login_logo
          break
        end
        sleep 1
      end
      unless login_logo
        parse_result[:msg] = 'login_fail'
        driver.save_screenshot("screenshots/be_login_fail.png")

        return parse_result
      end
      parsed_email_el = nil
      (1..10).each do
        parsed_email_el = driver.find_element(css: 'a#email') rescue nil
        break if parsed_email_el
        sleep 1
      end

      if parsed_email_el.nil?
        parse_result[:msg] = 'unknown_error'
        logger.error('be_auth_no_email_btn1')

        return parse_result
      end
      parsed_email = parsed_email_el.text.strip
      unless parsed_email.empty?
        parse_result[:success] = true
        parse_result[:email] = parsed_email

        return parse_result
      end

      captcha_result = captcha_resolve
      (1..5).each do
        parsed_email = driver.find_element(css: 'a#email').text.strip rescue ''
        if parsed_email.length > 0
          break
        end
        sleep 5
      end
      driver.save_screenshot("screenshots/be_captcha_result.png")
      logger.info "parsed email = #{parsed_email}"
      if parsed_email && parsed_email.length > 0
        parse_result[:email] = parsed_email
      end
      if parse_result[:email]
        parse_result[:success] = true
      end
      parse_result[:msg] = captcha_result

      parse_result
    end

    def self.captcha_resolve
      button = nil
      (1..10).each do
        button = driver.find_element(css: '#view-email-button-container div.yt-spec-touch-feedback-shape__fill') rescue nil
        break if button
        sleep 1
      end

      if button.nil?
        logger.error('be_auth_no_email_btn')

        return 'unknown_error'
      end
      button.click
      captcha_iframe = nil
      (1..10).each do
        captcha_iframe = driver.find_element(css: 'iframe[src*=recaptcha]') rescue nil
        break if captcha_iframe
        sleep 1
      end

      return 'no_captcha' if captcha_iframe.nil?
      O14::RucaptchaClient.recaptcha2(O14::Config.get_config.rucaptcha_key)
                          .current_url {driver.current_url}
                          .captcha_token do
        driver.execute_script(%q| document.querySelector('#g-recaptcha-response').style.display = 'block'|)
        driver.execute_script %q| document.querySelector('#g-recaptcha-response').value = ''|
        rc_frame = driver.find_element(css: 'iframe[src*=recaptcha]')
        uri = URI(rc_frame.attribute('src'))
        URI.decode_www_form(uri.query).to_h['k']
      end
                          .captcha_input do |captcha_code|
        logger.info captcha_code
        response_input = driver.find_element(id: 'g-recaptcha-response')
        response_input.send_keys captcha_code.force_encoding('utf-8')
      end
                          .submit do |captcha_code|
        driver.find_element(css: '#submit-btn').click
      end
                          .check_bad_captcha do
        result = false
        response_input = driver.find_element(id: 'g-recaptcha-response') rescue nil
        if response_input
          result = true
        end
        result
      end
                          .start
      'captcha_attempt'
    end
  end
end