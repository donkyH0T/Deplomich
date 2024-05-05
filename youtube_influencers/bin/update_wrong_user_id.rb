#!/usr/bin/env ruby
$:.unshift(File.expand_path('../lib', __dir__))

require 'o14/o14'
require 'y_i_parser'

def send_profile_msg(infl_row)
  O14::RMQ.send_message @input_exchage, infl_row
end

@input_exchage = O14::RMQ.get_channel.direct('exchange.tmp_problem_userid', durable: true)

logger = O14::ProjectLogger.get_logger 'INFO'
# p O14::DB.get_db[:YouTubeInfluencers].where(Sequel.lit("UpdatedAt > '2022-08-16 16:14:11.3066667'")).order(:id).limit(1)
params = {
  'host' => 'smi-db-ireland.ctonnmgtbe2i.eu-west-1.rds.amazonaws.com',
  'port' => '11433',
  'database' => 'Prod.Filed.SMI.Influencers',
  'user' => 'mikhail',
  'password' => 'mikhail@*',
}
@prod_db = O14::DB.create_connection params

queue = O14::RMQ.get_channel.queue('queue.tmp_update_userid', durable: true)
queue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, body|
	msg = JSON.parse(body, symbolize_names: true)
	logger.info "#{msg[:yi_id]}"
	begin
	  @prod_db[:YouTubeInfluencers].where(id: msg[:yi_id]).update(userid: msg[:new_user_id])
	rescue Sequel::UniqueConstraintViolation
	  send_profile_msg msg
	end
	O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
rescue => e
    logger.error e.inspect
    O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
end