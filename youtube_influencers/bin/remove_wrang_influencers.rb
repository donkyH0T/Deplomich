#!/usr/bin/env ruby
$:.unshift(File.expand_path('../lib', __dir__))

require 'o14/o14'
require 'y_i_parser'

def send_profile_msg(infl_row)
  O14::RMQ.send_message @input_exchage, infl_row
end

@input_exchage = O14::RMQ.get_channel.direct('exchange.tmp_update_userid', durable: true)

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
params = {
  'host' => 'smi-db-ireland.ctonnmgtbe2i.eu-west-1.rds.amazonaws.com',
  'port' => '11433',
  'database' => 'Dev3.Filed.SMI.Influencers',
  'user' => 'mikhail',
  'password' => 'mikhail@*'
}
@dev_db = O14::DB.create_connection params
stat_id = @prod_db[:YouTubeInfluencers].order(:id).limit(1).first[:id]
stat_id = 1189000
end_id = @prod_db[:YouTubeInfluencers].reverse_order(:id).limit(1).first[:id]
counter = 0
while end_id > stat_id
  rows = @prod_db["SELECT YI.Id, YI.UserId, I.UserId as inf_user_id, YI.UserName FROM YouTubeInfluencers as YI
JOIN Influencers as I ON I.Id = YI.InfluencerId WHERE YI.Id >= ? AND YI.Id < ?;", stat_id, stat_id + 3000].all
  stat_id += 3000
  
  rows.each do |row|
	if row[:userid].match(/^[0-9]+$/)
	  counter += 1
	  new_user_id = @dev_db["SELECT YI.UserId, I.UserName FROM Influencers as I
	  JOIN YouTubeInfluencers as YI ON YI.InfluencerId = I.Id
	  WHERE I.UserId = ?", row[:inf_user_id]].first[:userid]
	  msg = {new_user_id: new_user_id, yi_id: row[:id]}
	  send_profile_msg msg
	end
  end
  logger.info "counter #{counter}, stat_id #{stat_id}"
end