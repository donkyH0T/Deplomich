# frozen_string_literal: true
$:.unshift(File.expand_path('../lib', __dir__))

require 'o14/o14'
require 'sinatra'
require 'json'


set :port, 4567

logger = O14::ProjectLogger.get_logger 'INFO'

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
  response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
end

options '*' do
  response.headers['Access-Control-Allow-Origin'] = '*'
  response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
  200
end

get '/api/data/page/:page' do
  content_type :json
  page = params[:page].to_i
  offset = (page - 1) * 20
  data = O14::DB.get_db["SELECT * FROM youtubeinfluencers ORDER BY id DESC LIMIT 20 OFFSET ?;", offset].all
  total_count = O14::DB.get_db["SELECT COUNT(*) FROM youtubeinfluencers;"].first[:count]
  total_pages = (total_count / 20.0).ceil
  { data: data, total_pages: total_pages }.to_json
end

get '/api/data/account/:username' do
  content_type :json
  username = params['username']
  logger.info("get api/data for username: #{username}")
  query = 'SELECT * FROM youtubeinfluencers
           LEFT JOIN youtubeposts ON youtubeinfluencers.id = youtubeposts.youtubeinfluencerid
           WHERE youtubeinfluencers.username = ? ORDER BY youtubeposts.comment DESC, youtubeposts.view DESC'
  result = O14::DB.get_db[query, username].first.to_json
  result
end

get '/api/accounts' do
  content_type :json
  sort_type = params['sort']
  sort_direction = params['direction']
  search_value = params['search']
  logger.info("fetching data with sort type: #{sort_type}, sort direction: #{sort_direction}, and search value: #{search_value}")
  if search_value && !search_value.empty? && sort_type && sort_type == 'username' && sort_direction == 'asc'
    return O14::DB.get_db["SELECT * FROM youtubeinfluencers WHERE username LIKE ? ORDER BY username LIMIT 20",search_value + '%'].all.to_json
  end
  if search_value && !search_value.empty? && sort_type && sort_type == 'username' && sort_direction == 'DESC'
    return O14::DB.get_db["SELECT * FROM youtubeinfluencers WHERE username LIKE ? ORDER BY username DESC LIMIT 20",search_value + '%'].all.to_json
  end
  if search_value && !search_value.empty? && sort_type && sort_type == 'followers' && sort_direction == 'DESC'
    return O14::DB.get_db["SELECT * FROM youtubeinfluencers WHERE username LIKE ? ORDER BY followers DESC LIMIT 20",search_value + '%'].all.to_json
  end
  if search_value && !search_value.empty? && sort_type && sort_type == 'followers' && sort_direction == 'asc'
    return O14::DB.get_db["SELECT * FROM youtubeinfluencers WHERE username LIKE ? ORDER BY followers LIMIT 20",search_value + '%'].all.to_json
  end
  if search_value && !search_value.empty?
    return O14::DB.get_db["SELECT * FROM youtubeinfluencers WHERE username LIKE ?",search_value + '%'].all.to_json
  end
  if sort_type == 'username' && sort_direction == 'desc'
    return O14::DB.get_db["SELECT * FROM youtubeinfluencers ORDER BY username DESC LIMIT 20"].all.to_json
  end
  if sort_type == 'username' && sort_direction == 'asc'
    return O14::DB.get_db["SELECT * FROM youtubeinfluencers ORDER BY username LIMIT 20"].all.to_json
  end
  if sort_type == 'followers' && sort_direction == 'asc'
    return O14::DB.get_db["SELECT * FROM youtubeinfluencers ORDER BY followers LIMIT 20"].all.to_json
  end
  if sort_type == 'followers' && sort_direction == 'desc'
    return O14::DB.get_db["SELECT * FROM youtubeinfluencers ORDER BY followers DESC LIMIT 20"].all.to_json
  end
  O14::DB.get_db["SELECT * FROM youtubeinfluencers LIMIT 20"].all.to_json
end


post '/api/run-script' do
  logger.info('run-script')

  command_hashtags_queue_filler = '/home/donkyhot/Desktop/Deplomich/youtube_influencers/bin/run hashtags_queue_filler --log_level=INFO'
  command_hashtags_agent = '/home/donkyhot/Desktop/Deplomich/youtube_influencers/bin/run hashtags_agent --log_level=INFO'
  command_profile_agent = '/home/donkyhot/Desktop/Deplomich/youtube_influencers/bin/run profile_agent --log_level=INFO'
  command_video_process_agent = '/home/donkyhot/Desktop/Deplomich/youtube_influencers/bin/run video_process_agent --log_level=INFO'
  command_export_agent = '/home/donkyhot/Desktop/Deplomich/youtube_influencers/bin/run export_agent --log_level=INFO'
  spawn(command_export_agent)
  begin
    threads = []
    [command_hashtags_queue_filler, command_hashtags_agent, command_profile_agent, command_video_process_agent].each do |command|
      threads << Thread.new { `#{command}` }
    end
    sleep(120)
    threads.each(&:exit)
    logger.info("Script executed successfully")
    status 200
    return body "Script executed successfully"
  rescue
    logger.error("Error executing script")
    status 500
    return body "Error executing script"
  end
end

post '/api/stop-script' do
  logger.info('stop-script')
  export_agent_kill = 'pkill -f export_agent'
  hashtags_queue_filler_kill = 'pkill -f hashtags_queue_filler'
  hashtags_agent_kill = 'pkill -f hashtags_agent'
  profile_agent_kill = 'pkill -f profile_agent'
  video_process_agent_kill = 'pkill -f video_process_agent'
  begin
    spawn(export_agent_kill)
    spawn(hashtags_queue_filler_kill)
    spawn(hashtags_agent_kill)
    spawn(profile_agent_kill)
    spawn(video_process_agent_kill)
    logger.info("Script stopped successfully")
    status 200
    return body "Script stopped successfully"
  rescue
    logger.error("Error stopping script")
    status 500
    return body "Error stopping script"
  end
end


