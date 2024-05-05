#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'o14/o14'

logger = O14::ProjectLogger.get_logger 'INFO'


min_id = O14::DB.get_db['SELECT MIN(id) FROM youtubeinfluencers'].first[:min]
max_id = O14::DB.get_db['SELECT MAX(id) FROM youtubeinfluencers'].first[:max]
while min_id < max_id
  query = "SELECT Date(yh.createdat) as createdat, yh.followers,yh.engagementrate, yh.averagecomments, yh.averagelikes, yh.views, yh.engagementperpost, yh.averageviews, yh.userid, yh.posts FROM youtubeinfluencers as y
           JOIN youtubeinfluencers_history as yh ON yh.userid = y.userid
           WHERE y.id >= ? AND y.id < ?
           ORDER BY yh.userid, Date(yh.createdat) DESC;"
  last_created = Date.new
  last_userid = ''
  O14::DB.get_db[query, min_id, min_id + 1000].all.each do |youtubeinfluencer|
    if last_created == youtubeinfluencer[:createdat] && last_userid == youtubeinfluencer[:userid]
      logger.info youtubeinfluencer[:userid]
    else
      O14::DB.get_db[:youtubeinfluencers_history_fixed].insert_conflict.insert(youtubeinfluencer)
    end
    last_created = youtubeinfluencer[:createdat]
    last_userid = youtubeinfluencer[:userid]
  end
  min_id += 1000
  logger.info(min_id)
end
