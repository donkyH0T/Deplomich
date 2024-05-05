# frozen_string_literal: true

require 'down'
require 'uri'
require 'aws-sdk-s3'

module O14
  class StorageClient
    def initialize(region, access_key, secret_key)
      Aws.config.update({
                          region: region,
                          credentials: Aws::Credentials.new(access_key, secret_key)
                        })
      @s3 = Aws::S3::Resource.new
      @logger = O14::ProjectLogger.get_logger
    end

    def upload(bucket, folder, object_name, image_body, content_type, change_if_exist)
      obj = @s3.bucket(bucket).object("#{folder}/#{object_name}")
      if change_if_exist
        obj.put(body: image_body, content_type: content_type, acl: 'private')
      elsif !obj.exists?
        obj.put(body: image_body, content_type: content_type, acl: 'private')
      end
      obj.public_url
    rescue StandardError => e
      @logger.error "upload - Exception: #{e.class.name} #{e.message}"
      @logger.error "Exception Backtrace: #{e.backtrace}"
      false
    end

    def remove(bucket, folder, object_name)
      obj = @s3.bucket(bucket).object("#{folder}/#{object_name}")
      obj.delete
    end

    def get_objects_in_folder(bucket, folder, continuation_token = nil)
      s3_client = @s3.client
      prefix = "#{folder}/"
      params = { bucket: bucket, prefix: prefix }
      params[:continuation_token] = continuation_token if continuation_token
      s3_client.list_objects_v2(params)
    end
  end

  class FileUploader
    @logger = ProjectLogger.get_logger
    @config = Config.get_config
    BUCKET = @config.s3_storage['bucket']
    REGION = @config.s3_storage['region']
    FILE_MAX_SIZE = 30 * 1024 * 1024
    MAX_REDIRECTS = 5

    def self.download_file(url)
      begin
        remote_file = Down.open(url, max_size: FILE_MAX_SIZE, max_redirects: MAX_REDIRECTS)
        temp_file = remote_file.read
        remote_file.close
      rescue Down::TooLarge
        @logger.error 'file too larcge'
        return { success: false, error: 'too_large' }
      rescue Down::ClientError, Down::ConnectionError, Down::TimeoutError, Down::SSLError, Down::InvalidUrl => e
	    if e.message.match /URL scheme needs to be http or https/
		    @logger.error "Incorrect_url"
			return {:success => false, :error => 'incorrect_url'}
		end
		if e.message.match /timed out waiting/
			@logger.error "timed out waiting"
			return {:success => false, :error => 'timeout_error'}
		end
	    if e.message.match /SSL_connect/
		    @logger.error "SSL_connect"
			return {:success => false, :error => 'ssl_error'}
		end
        if e.message.match(/403 Forbidden/)
          @logger.info '403 Forbidden'
          return { success: false, error: 'forbidden' }
        end
        if e.message.match(/404 Not Found/)
          @logger.info '404 Not Found'
          return { success: false, error: 'not_found' }
        end
        if e.message.match(/410 Gone/)
          @logger.info '410 Gone'
          return { success: false, error: 'gone_away' }
        end
        if e.message.match(/Failed to open TCP/)
          @logger.info 'Failed to open TCP'
          return { success: false, error: 'connection_error' }
        end
        if e.message.match(/400 Bad Request/)
          @logger.info '400 Bad Request'
          return { success: false, error: 'bad_request' }
        end
        if e.message.match(/466 Status Code 466/) || e.message.match(/466 Unknown/)
          @logger.info 'fail to get resource'
          return { success: false, error: 'bad_request' }
        end
        @logger.error "download_img - Exception: #{e.class.name} #{e.message}"
        @logger.error "Exception Backtrace: #{e.backtrace}"
        return { success: false, error: 'unknown' }
      rescue Down::ServerError => e
        if e.message.match(/500 Internal Server Error/)
          @logger.error '500 Internal Server Error'
          return { success: false, error: 'internal_server_error' }
        end
      rescue StandardError => e
        @logger.error "download_img - Exception: #{e.class.name} #{e.message}"
        @logger.error "Exception Backtrace: #{e.backtrace}"
        return { success: false, error: 'unknown' }
      end
      { success: true, file: temp_file }
    end

    def self.generate_name(origin, file_extension)
      "#{Digest::MD5.hexdigest(origin)}.#{file_extension}"
    end

    def self.save_to_storage(body, name, dir, content_type, change_if_exist = false)
      storage_client = StorageClient.new(@config.s3_storage['region'], @config.s3_storage['id'],
                                         @config.s3_storage['secret'])
      storage_client.upload(BUCKET, dir, name, body, content_type, change_if_exist)
    end

    def self.upload_file_from_url(url, name, dir, content_type)
      response = download_file url
      return { success: false, error: response[:error] } if response[:success] == false

      url = save_to_storage response[:file], name, dir, content_type
      return { success: true, url: url } if url

      { success: false, error: 'unknown' }
    end

    def self.remove_file(url, dir)
      storage_client = StorageClient.new @config.s3_storage['region'], @config.s3_storage['id'],
                                         @config.s3_storage['secret']
      img_name = URI.parse(url).path.split('/').last
      storage_client.remove BUCKET, dir, img_name
    end
  end
end
