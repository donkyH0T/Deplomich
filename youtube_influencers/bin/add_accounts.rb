#!/usr/bin/env ruby
$:.unshift(File.expand_path('../lib', __dir__))

require 'o14/o14'
require 'y_i_parser'

logger = O14::ProjectLogger.get_logger 'INFO'

accounts_file_path = File.join(__dir__, '..', 'tmp', 'accounts.txt')
if File.exists?(accounts_file_path) == false
  logger.error "File #{accounts_file_path} not exist"
  exit
end
 
accounts = File.read(accounts_file_path).split("\n")
logger.info "#{accounts.count} accounts detected"

counter = 0
accounts.each do |account|
  acc_parts = account.split(":")
  exist_acc = O14::DB.get_db[:google_accounts].where(:email => acc_parts[0]).first
  if exist_acc
    logger.info "Account #{account} is exist"
  else
    O14::DB.get_db[:google_accounts].insert(:email => acc_parts[0], :password => acc_parts[1], :submail => acc_parts[2])
    counter += 1
  end
end

logger.info "#{counter} accounts inserted"