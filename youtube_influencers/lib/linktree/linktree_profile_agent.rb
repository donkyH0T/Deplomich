module YIParser
	class LinktreeProfileAgent
		@config = O14::Config.get_config

		@profile_queue = O14::RMQ.get_channel.queue(@config.infrastructure['linktree_queue'], durable: true)
		
		@export_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['export_exchange'], durable: true)

		
		def self.logger
			O14::ProjectLogger.get_logger
		end
		
		def self.run
			logger = O14::ProjectLogger.get_logger
			@profile_queue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, body|
				msg = JSON.parse(body, symbolize_names: true)
				proxy = ProxiesManager.get_random_proxy('ipv4')
				if proxy.nil?
					O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
					logger.info 'No proxies. Sleeping 10 sec...'
					sleep 10
					next
				end
				
				logger.debug proxy
				process_profile msg, proxy
				O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
			rescue Bunny::Session
				O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
				logger.error "#{Time.now} - Bunny::Session Error"
			rescue => e
				O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
				logger.error "#{$!.class.name}\n#{$!.message}\n#{$!.backtrace.join("\n")}"
			end
		end
		
		def self.process_profile msg, proxy
			nickname = msg[:data][:nickname]
			userid = msg[:data][:userid]
			
			if nickname == 'admin'
				logger.debug "nickname is admin, skip"
				
				return true
			end
			
			logger.debug "Linktree nickname #{nickname}"
			init_data = LinktreeHttpClient.get_profile_data(nickname, proxy)
			if init_data[:error]
				if init_data[:error] == 'Page not found'
					logger.debug "Page not found"
					return true
				end
				raise init_data[:error]
			end
			
			profile = parse_profile_data init_data
			msg = {
				type: 'linktree_profile',
				data: {
					nickname: nickname,
					userid: userid,
					profile_data: init_data.to_json,
					email: profile[:email],
					possible_email: profile[:possible_email]
				}
			}
			O14::RMQ.send_message @export_exchange, msg
		end
		
		def self.parse_profile_data init_data
			email = get_email init_data
			possible_email = false
			if email.nil?
				possible_email = detect_possible_email_case init_data
			end
			{
				email: email,
				possible_email: possible_email
			}
		end
		
		def self.get_email init_data
			if init_data['props']['pageProps']['socialLinks']
				enail_el = init_data['props']['pageProps']['socialLinks'].find{|_e| _e['type'] == 'EMAIL_ADDRESS'}
				if enail_el
					return enail_el['url'].gsub('mailto:', '')
				end
			end
			if init_data['props']['pageProps']['links']
				enail_el = init_data['props']['pageProps']['links'].find{|_e| _e['url'] =~ /mailto:/}
				if enail_el
					return enail_el['url'].gsub('mailto:', '')
				end
			end
			nil
		end
		
		def self.detect_possible_email_case init_data
			str_init_data = init_data.to_json
			str_init_data = str_init_data.gsub('isEmailVerified', '')
			if str_init_data =~ /mailto/ || str_init_data =~ /email/i
				return true
			end
			false
		end
	end
end