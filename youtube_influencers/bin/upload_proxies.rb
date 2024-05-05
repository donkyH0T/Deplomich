#!/usr/bin/env ruby
$:.unshift(File.expand_path('../lib', __dir__))

require 'o14/o14'
require 'y_i_parser'

logger = O14::ProjectLogger.get_logger 'INFO'

proxies_file_path = File.join(__dir__, '..', 'tmp', 'proxies.txt')
if File.exists?(proxies_file_path) == false
  logger.error "File #{proxies_file_path} not exist"
  exit
end

proxies_type = ARGV.first

if proxies_type.nil?
	logger.error 'Proxies type not specified'
    exit
end
 
proxies = File.read(proxies_file_path).split("\n")
logger.info "#{proxies.count} proxies detected"
proxies.each do |proxy|
  begin
  	O14::DB.get_db[:proxies].insert(:address => proxy, :is_processed => false, :last_success => false, :type => proxies_type)
  rescue Sequel::UniqueConstraintViolation
    logger.info "#{proxy} already exist"
  end
end

logger.info "All proxies inserted"