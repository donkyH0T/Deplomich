require 'logger'
require 'rest-client'
require 'timeout'

=begin

Использовать как-то так:

captcha = RucaptchaClient.recaptcha2(RUCAPTCHA_KEY)
captcha
	.current_url(driver.current_url)
	.captcha_token do
		driver.execute_script(%q| document.querySelectorAll('iframe').forEach( item => item.contentWindow.document.getElementById('g-recaptcha-response').style.display = 'block')|)
		driver.execute_script %q| document.querySelectorAll('iframe').forEach( item => item.contentWindow.document.getElementById('g-recaptcha-response').value = '');|
		rc_frame = driver.find_element(css: 'iframe[src*=recaptcha]')
		rc_frame.attribute('src')[/[\?\&]k\=([^\&]+)/,1]
	end
	.captcha_input do |captcha_code|
		iframe = driver.find_element(css: 'iframe')
		driver.switch_to.frame iframe
		response_input = driver.find_element(id: 'g-recaptcha-response')
		response_input.send_keys captcha_code.force_encoding('utf-8')
	end
	.submit {|captcha_code| driver.execute_script("onCaptchaFinished(\"#{captcha_code}\");") }
	.check_bad_captcha { driver.find_element(css:'.error').text != '' }
	.start

=end
module O14
  module RucaptchaClient
	def self.recaptcha2 rucaptcha_key
		Recaptcha2Resolver.new(rucaptcha_key)
	end

	class RucaptchaError < StandardError ; end
	class ResolveCaptchaFailed < StandardError ; end

	class Recaptcha2Resolver
		def initialize rucaptcha_key
			@rucaptcha_key = rucaptcha_key
			@tries = 1
			@logger = O14::ProjectLogger.get_logger
		end

		def logger logger
			@logger = logger

			self
		end

		def current_url  &block
			@current_url_action = block

			self
		end

		def captcha_token  &block
			@captcha_token_action = block

			self
		end

		def captcha_input &block
			@captcha_input_action = block

			self
		end

		def tries tries_qty
			@tries = tries_qty

			self
		end

		def submit &block
			@submit_action = block

			self
		end

		def check_bad_captcha &block
			@check_bad_captcha_action = block

			self
		end

		def on_retry &block
			@on_retry_action = block

			self
		end

		def start
			@logger.info 'initializing recaptcha solver'

			raise RucaptchaError, '"check_bad_captcha_action" must be specified' unless @check_bad_captcha_action

			tries = @tries
			while tries > 0
				@logger.info "try: #{@tries - tries + 1}"
				begin
					success = try_resolve_captcha
				rescue RucaptchaError
					@logger.error "recaptcha error: #{$!.message}"
					success = false
				end
				@logger.info "captcha successfulness: #{success}"

				# если неправильная пробуем снова
				if success
					@logger.info "Captcha resolved!!!!"
					return
				end

				resp_report = RestClient.get(
					'http://rucaptcha.com/res.php',
					{
						params:	{
							key: @rucaptcha_key,
							action: 'reportbad',
							id: @captcha_id
						}
					}
				)
				@logger.debug @captcha_id
				@logger.debug "resp_report got #{resp_report.to_str}"

				@on_retry_action.call if @on_retry_action

				tries -= 1
			end

			# raise ResolveCaptchaFailed
		end

		private

		def try_resolve_captcha
			@logger.info "getting page url"
			url = @current_url_action.call
			# получаем значение токена
			@logger.info "getting token"
			token = @captcha_token_action.call

			@logger.info "receiving result from rucaptcha"
			# first request
			resp = RestClient.get(
				'http://rucaptcha.com/in.php',
				{
					params:	{
						key: @rucaptcha_key,
						method: 'userrecaptcha',
						googlekey: token,
						pageurl: url
					}
				}
			)

			code, captcha_id = resp.to_str.split('|')
			@captcha_id = captcha_id

			unless code == 'OK'
				raise RucaptchaError, 'Wrong response for token: %s' % resp.to_str
			end


			result_response = nil
			begin
				Timeout::timeout(120) do
					# second request
					loop do
						resp2 = RestClient.get(
							'http://rucaptcha.com/res.php',
							{
								params:	{
									key: @rucaptcha_key,
									action: 'get',
									id: captcha_id
								}
							}
						)
						@logger.debug "resp2 got #{resp2.to_str}"
						resp2_code, result_response = resp2.to_str.split('|', 2)

						unless resp2_code == 'CAPCHA_NOT_READY'
							if resp2_code == 'OK'
								break
							else
								raise RucaptchaError, 'Problem with second response: %s' % resp2_code
							end
						end

						sleep 10
					end
				end
			rescue Timeout::Error
				raise RucaptchaError, 'Too slow recaptcha solving'
			end

			# вводим
			@logger.info "entering captcha"
			@captcha_input_action.call(result_response)

			# правильная ли капча?
			@logger.info "submitting"
			@submit_action.call(result_response)
			@logger.info "checking corectness"
			!@check_bad_captcha_action.call
		end
	end
  end # RucaptchaClient
end # O14