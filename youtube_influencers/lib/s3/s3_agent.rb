# frozen_string_literal: true

require 'json'
require 'rmagick'

module YIParser
  class S3Agent
    QUEUE_NAME = O14::Config.get_config.infrastructure['s3_queue']
    EXCHANGE_EXPORT_NAME = O14::Config.get_config.infrastructure['export_exchange']
    S3_PROFILE_IMG = O14::Config.get_config.infrastructure['redis_keys']['s3_profile_img_hash_name']
    S3_IMAGES_FOLDER = 'imgs'

    @export_exchange = O14::RMQ.get_channel.direct(EXCHANGE_EXPORT_NAME, durable: true)

    def self.run(log_level = 'ERROR', log_filename = nil)
      @logger = O14::ProjectLogger.get_logger log_level#, log_filename
      queue = O14::RMQ.get_channel.queue(QUEUE_NAME, durable: true)

      begin
        queue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, body|
          result = handle_s3_msg delivery_info, body
          if result[:success]
            O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
          else
            if ['gone_away', 'forbidden', 'not_found', 'connection_error', 'server_error', 'internal_server_error', 'bad_request'].include? result[:error]
              O14::RMQ.get_channel.reject(delivery_info.delivery_tag, false)
            else
              O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
            end
          end
        rescue => e
          @logger.error e.inspect
          O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        end
      rescue Interrupt
        @logger.error 'Interrupted...'
      end
    end

    def self.handle_s3_msg(_delivery_info, body)
      msg = JSON.parse(body)
      youtube_userid = msg['youtube_userid']
      original_url = msg['original_url']

      @logger.info "original_url = #{original_url}"
      response = O14::FileUploader.download_file(original_url)
      unless response[:success]
        return { success: false, error: response[:error] }
      end

      file = response[:file]      
      magick_image = Magick::Image::from_blob(file).first
      new_file_name = O14::FileUploader.generate_name(magick_image.signature, 'jpg')
      new_url = O14::FileUploader.save_to_storage(file, new_file_name, S3_IMAGES_FOLDER, 'image/jpeg')
      @logger.info "generated image url = #{new_url}"
      if new_url == false
        return {success: false, error: 'unknown'}
      end

      send_export_msg(youtube_userid, new_url)
      {success: true}
    end

    def self.send_export_msg(youtube_userid, new_url)
      return if new_url.nil?

      data = {
        'youtube_userid' => youtube_userid,
        'ProfilePictureUrl' => new_url
      }
      export_msg = {
        'data' => data,
        'type' => 's3'
      }
      O14::RMQ.send_message @export_exchange, export_msg
    end
  end
end
