require 'sequel'
require 'date'

module YIParser
  class ExportAgent
    @config = O14::Config.get_config
    @logger = O14::ProjectLogger.get_logger
    @export_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['export_exchange'], durable: true)
    @face_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['face_exchange'], durable: true)
    RESULT_QUEUE = @config.infrastructure['export_queue']

    def self.db
      O14::DB.get_db
    end

    def self.logger
      O14::ProjectLogger.get_logger
    end

    def self.run
      @db = O14::DB.get_db
      export_queue = O14::RMQ.get_channel.queue(RESULT_QUEUE, durable: true)
      export_queue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, body|
        msg = JSON.parse(body, symbolize_names: true)
        if handle_export(msg)
          @logger.info 'ack'
          O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
        else
          @logger.info 'republish'
          O14::RMQ.send_message @export_exchange, msg
          O14::RMQ.get_channel.ack(delivery_info.delivery_tag)
        end
      rescue Bunny::Session
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        # @logger.error " - Bunny::Session... sleeping..."
        sleep 5
        exit
      rescue StandardError
        @logger.error(" - Error. #{$!.message}\n#{$!.backtrace.join("\n")}")
        @logger.error("message = #{msg}")
        O14::RMQ.get_channel.reject(delivery_info.delivery_tag, true)
        sleep 5
        exit
      end
    end

    def self.handle_export(msg)
      @logger.debug("handle msg type: #{msg[:type]}")
      case msg[:type]
      when 'profile'
        data = mapping_data_profile(msg[:data])
        if msg[:data][:emails].nil?
          emails = process_email(msg[:data][:email], 'bio')
        else
          emails = msg[:data][:emails]
        end
        process_profile(data, emails)
        return true
      when 'old_userid'
        add_old_userid(msg[:data])
        return true
      when 'profile_video'
        data = mapping_video_profile_data(msg[:data])
        return process_profile_video(data, msg[:data][:youtube_userid])
      when 'video'
        return process_video(msg[:data])
      when 's3'
        return process_s3(msg[:data])
      when 'face_recognition'
        return process_face_recognition(msg[:data])
      when 'linktree_profile'
        return process_linktree_profile(msg[:data])
      when 'influencer_emails'
        return process_influencer_emails(msg[:data])
      when 'is_business_email_exist'
        return set_business_email_exist(msg[:data])
      when 'add_profile_hashtag'
        return add_profile_hashtag(msg[:data])
      end
    end

    def self.add_profile_hashtag(data)
      data[:user_ids].each do |userid|
        sql = 'select hashtags, id from youtubeinfluencers
          where userid = ?'
        influencer_row = db[sql, userid].first
        if influencer_row
          old_hashtags = YIParser::Utils.process_hashtags_from_string(influencer_row[:hashtags])
          unless old_hashtags.include?(data[:hashtag])
            old_hashtags.push(data[:hashtag])
            db[:youtubeinfluencers].where(id: influencer_row[:id]).update(:hashtags => old_hashtags.join(' '), :is_migrated => 0)
          end
        end
      end
      true
    end

    def self.process_email text, source
      influencer_emails = []
      emails = YIParser::Utils.get_all_emails(text)
      emails.each do |email|
        email = YIParser::Utils.complete_email_domain(email)
        is_correct = YIParser::Utils.is_email_syntax_correct(email)
        influencer_emails.push({
                                 email: email,
                                 source: source,
                                 is_correct: is_correct
                               })
      end
      influencer_emails
    end

    def self.send_face_msg(user_id, new_url)
      return if new_url.nil?

      face_msg = {
        'user_id' => user_id,
        'profile_pic_url_hd' => new_url
      }
      O14::RMQ.send_message(@face_exchange, face_msg)
    end

    def self.process_s3(data)
      # if data[:ProfilePictureUrl].nil? || data[:ProfilePictureUrl].empty?
      #   return true
      # end
      # query = "SELECT id, profilepicture FROM youtubeinfluencers WHERE userid = ?;"
      # influencer_row = @db[query, data[:youtube_userid]].first
      # @logger.debug("influencer_row: #{influencer_row}")
      # if influencer_row.nil?
      #   return false
      # end
      # if !influencer_row[:profilepicture].nil? && !influencer_row[:profilepicture].empty? && influencer_row[:profilepicture] != data[:ProfilePictureUrl]
      #   @storage_client.remove(@config.s3_storage['bucket'], 'imgs', influencer_row[:profilepicture].split('/').last)
      # end
      # if influencer_row[:profilepicture].nil? || influencer_row[:profilepicture].empty? || influencer_row[:profilepicture] != data[:ProfilePictureUrl]
      #   send_face_msg(data[:youtube_userid], data[:ProfilePictureUrl])
      #   @db[:youtubeinfluencers].where(:id => influencer_row[:id]).update(:profilepicture => data[:ProfilePictureUrl], :is_migrated => 0)
      # end
      true
    end
    
    def self.add_old_userid(data)
      if data[:userid].nil? || data[:userid].empty?
        return true
      end
      @db[:youtubeinfluencers].where(userid: data[:userid]).update(old_userid: data[:old_userid])
    end

    def self.process_face_recognition(data)
      query = "SELECT id FROM youtubeinfluencers WHERE userid = ?;"
      influencer_row = @db[query, data[:user_id]].first
      @logger.debug("influencer_row: #{influencer_row}")
      if influencer_row.nil?
        return false
      else
        ages = nil
        if data[:age]
          ages = data[:age].uniq.join(',')
        end
        genders = nil
        if data[:gender]
          genders = data[:gender].join(',')
        end
        @db["youtubeinfluencers".to_sym].where(:id => influencer_row[:id]).update(:ages => ages, :gender => genders, :is_migrated => 0, :is_face_recalculated => true)
      end
      return true
    end
    def self.mapping_data_profile(all_data)
      data = all_data[:channel]
      if data.nil?
        data = all_data
      end
      data[:views] = 0 if data[:views].nil?
      unless data[:title].nil?
        data[:title] = YIParser::Utils.reject_null_unicode_symbals(data[:title])
      end
      unless data[:description].nil?
        data[:description] = YIParser::Utils.reject_null_unicode_symbals(data[:description])
      end
      if data[:user_id].nil?
        matched = data[:url].match(/youtube\.com\/channel\/(.+)/)
        if matched
          data[:user_id] = matched[1]
        end
      end
      data[:email]
      new_data = {
        :updatedat => DateTime.parse(data[:updated_at]),
        :username => data[:username],
        :title => data[:title],
        :userid => data[:user_id],
        :followers => data[:subscribers_count].to_i,
        :engagementrate => 0,
        :totalengagement => 0,
        :engagementperpost => 0,
        :biography => data[:description],
        :views => data[:views],
        :originprofilepicture => data[:profile_picture],
        :source => data[:source],
        :external_links => data[:external_links].join(','),
        :originalsource => data[:original_source],
        :postinterval => data[:post_interval],
        :is_verified => data[:verified],
        :is_business_email_exist => data[:is_business_email_exist],
        :source_table => data[:source_table],
        :posts => data[:posts],
        :is_migrated => 0,
        :is_updated => false
      }
      if data[:old_userid] && !data[:old_userid].empty?
        new_data[:old_userid] = data[:old_userid]
      end
      if data[:country] && !data[:country].empty?
        new_data[:country] = data[:country]
      end
      new_data
    end

    def self.mapping_video_profile_data(data)
      data[:external_tags] = [] if data[:external_tags].nil?
      new_data = {
        hashtags: data[:hashtags],
        externaltags: data[:external_tags],
        averagecomments: data[:average_comments],
        averagelikes: data[:average_likes],
        averageviews: data[:average_views],
        engagementperpost: data[:engagement_per_post],
        engagementrate: data[:engagement_rate],
        is_migrated: 0
      }
      new_data
    end

    def self.process_profile(data, emails)
      emails = [] if emails.nil?
      @db.transaction do
        query = "SELECT id, hashtags FROM youtubeinfluencers WHERE userid = ?;"
        profile_row = @db[query, data[:userid]].first
        if profile_row.nil?
          youtube_influencer_id = @db["youtubeinfluencers".to_sym].insert(data)
          @logger.debug("Insert data: #{data} in youtubeinfluencers")
        else
          data = remove_empty_fields(data)
          if data[:hashtags].nil?
            data[:hashtags] = []
          end
          new_country = [data[:country]]
          profile_row[:country] = '' if profile_row[:country].nil?
          old_country = profile_row[:country].split(',').map { |_e| _e.strip }.reject { |_e| _e.empty? }
          data[:country] = (new_country + old_country).uniq.join(", ")
          unless profile_row[:hashtags].nil?
            hashtags = profile_row[:hashtags].split(/\p{Z}|,\p{Z}|#/).map { |_e| _e.gsub('#', '').gsub('?', '') }.reject { |_e| _e.empty? }
            unless data[:hashtags].nil?
              hashtags += data[:hashtags].map { |_e| _e.gsub('#', '').gsub('?', '') }.reject { |_e| _e.empty? }
              data[:hashtags] = hashtags.uniq
            end
          end
          data[:hashtags] = data[:hashtags].join(' ')
          @db["youtubeinfluencers".to_sym].where(:id => profile_row[:id]).update(data)
          @logger.debug("Update data: ud = #{profile_row[:id]}, data = #{data} in youtubeinfluencers")
          youtube_influencer_id = profile_row[:id]
        end
        update_influencer_emails(emails, youtube_influencer_id)

        @db["youtubeinfluencers_history".to_sym].insert_conflict.insert({
                                                                          createdat: data[:updatedat],
                                                                          followers: data[:followers],
                                                                          views: data[:views],
                                                                          posts: data[:posts],
                                                                          userid: data[:userid]
                                                                        })

      end
    end

    def self.remove_empty_fields hash_to_process
      hash_to_process.each do |key, value|
        if value.nil?
          hash_to_process.delete(key)
        else
          if value.instance_of?(String)
            value = value.strip
            if value.empty?
              hash_to_process.delete(key)
            end
          elsif value.is_a?(Integer)
            if value <= 0
              hash_to_process.delete(key)
            end
          elsif value.is_a?(Float)
            if value <= 0.0
              hash_to_process.delete(key)
            end
          end
        end
      end
      hash_to_process
    end

    def self.process_profile_video(data, user_id)
      @db.transaction do
        query = "SELECT id, followers, hashtags, externaltags FROM youtubeinfluencers WHERE userid = ?;"
        profile_row = @db[query, user_id].first
        if profile_row.nil?
          return false
        else
          latest_posts = @db["SELECT \"like\", view, comment FROM youtubeposts WHERE youtubeinfluencerid = ? ORDER BY postedat DESC LIMIT 12", profile_row[:id]].all
          posts_likes = 0
          posts_views = 0
          posts_comments = 0
          latest_posts.each do |post|
            post[:like] = 0 if post[:like].nil?
            posts_likes += post[:like]
            posts_views += post[:view]
            posts_comments += post[:comment]
          end
          data[:averagecomments] = (posts_comments.to_f / 12.0).round(2)
          data[:averagelikes] = (posts_likes.to_f / 12.0).round(2)
          data[:averageviews] = (posts_views.to_f / 12.0).round(2)
          data[:engagementperpost] = (data[:averagelikes].to_f + data[:averagecomments].to_f).round(2)
          if profile_row[:followers] > 0
            data[:engagementrate] = (data[:engagementperpost].to_f / profile_row[:followers].to_f * 100.0).round(2)
          else
            data.delete(:engagementrate)
          end
          data[:hashtags] = data[:hashtags].map { |_e| YIParser::Utils.reject_null_unicode_symbals(_e) }.reject { |_e| _e.strip.empty? }
          if data[:hashtags].empty?
            data.delete(:hashtags)
          else
            profile_row[:hashtags] = '' if profile_row[:hashtags].nil?
            old_hashtags = profile_row[:hashtags].split(/\p{Z}|,\p{Z}|#/).map { |_e| _e.gsub('#', '').gsub('?', '') }
            data[:hashtags] = (data[:hashtags] + old_hashtags).uniq.join(' ').strip
          end
          data[:externaltags] = data[:externaltags].map { |_e| YIParser::Utils.reject_null_unicode_symbals(_e) }.reject { |_e| _e.strip.empty? }
          if data[:externaltags].empty?
            data.delete(:externaltags)
          else
            profile_row[:externaltags] = '' if profile_row[:externaltags].nil?
            old_hashtags = profile_row[:externaltags].split(/\p{Z}|,\p{Z}|#/).map { |_e| _e.gsub('#', '').gsub('?', '') }
            data[:externaltags] = (data[:externaltags] + old_hashtags).uniq.join(' ').strip
          end
          @db["youtubeinfluencers".to_sym].where(:id => profile_row[:id]).update(data)
          history_row = @db["youtubeinfluencers_history".to_sym].where(:userid => user_id).reverse_order(:createdat).limit(1).first
          if history_row
            @db["youtubeinfluencers_history".to_sym].where(:userid => user_id, :createdat => history_row[:createdat]).update({
                                                                                                                               engagementrate: data[:engagementrate],
                                                                                                                               averagecomments: data[:averagecomments],
                                                                                                                               averagelikes: data[:averagelikes],
                                                                                                                               engagementperpost: data[:engagementperpost],
                                                                                                                               averageviews: data[:averageviews]
                                                                                                                             })
          end
          if profile_row[:id]
            remove_ids = []
            remove_posts = @db[:youtubeposts].select(:id, :postedat).where(:youtubeinfluencerid => profile_row[:id]).all.sort_by { |k| k[:postedat] }.reverse[12..-1]
            if remove_posts
              remove_ids = remove_posts.map { |_e| _e[:id] }
            end
            if remove_ids.count > 0
              @db[:youtubeposts].where(:id => remove_ids).delete
            end
          end
          @logger.debug("Update data: id = #{profile_row[:id]}, data = #{data} in youtubeinfluencers")
        end
      end
      true
    end

    def self.process_video(data)
      @db.transaction do
        youtube_influencer_id = @db["youtubeinfluencers".to_sym].select(:id).where(userid: data[:youtube_userid]).first
        if youtube_influencer_id.nil?
          return false
        end
        query = "SELECT id FROM youtubeposts WHERE postlink = ?;"
        video_row = @db[query, data[:post_link]].first
        if data[:posted_at] == '-4712-01-01'
          data[:posted_at] = Time.now
        end
        data[:title] = YIParser::Utils.reject_null_unicode_symbals(data[:title])
        data[:description] = YIParser::Utils.reject_null_unicode_symbals(data[:description])
        new_data = {
          postlink: data[:post_link],
          title: data[:title],
          description: data[:description],
          like: data[:like],
          comment: data[:comment],
          view: data[:view],
          postedat: data[:posted_at],
          youtubeinfluencerid: youtube_influencer_id[:id]
        }
        if data[:emails] && data[:emails].count > 0
          update_influencer_emails(data[:emails], youtube_influencer_id[:id])
        end
        if video_row.nil?
          @db["youtubeposts".to_sym].insert(new_data)
          @logger.debug("Insert data: #{new_data} in youtubeposts")
        else
          @db["youtubeposts".to_sym].where(:id => video_row[:id]).update(new_data)
          @logger.debug("Update data: id = #{video_row[:id]}, data = #{new_data} in youtubeposts")
        end
      end
      return true
    end

    def self.process_linktree_profile data
      user_id = data[:userid]
      row = db[:youtubeinfluencers].select(:id).where(userid: user_id).first
      if row.nil?
        logger.error('youtubeinfluencers doesn\'t exist')
        return false
      end
      youtube_influencer_id = row[:id]

      linktree_profile = {
        email: data[:email],
        nickname: data[:nickname],
        possible_email: data[:possible_email],
        profile_data: data[:profile_data]
      }
      linktree_row = db[:influencerlinktreeprofiles].select(:id).where(youtube_influencer_id: youtube_influencer_id).first
      if linktree_row
        db[:influencerlinktreeprofiles].where(id: linktree_row[:id]).update(linktree_profile)
      else
        linktree_profile[:youtube_influencer_id] = youtube_influencer_id
        db[:influencerlinktreeprofiles].insert(linktree_profile)
      end
      if data[:email]
        insert_email(data[:email], youtube_influencer_id, 'linktree', true)
        redefine_influencer_email(youtube_influencer_id)
      end

      return true
    end

    def self.insert_email email, youtube_influencer_id, source, is_correct
      already_inserted = db[:influenceremails].where(:email => email).where(:youtube_influencer_id => youtube_influencer_id).first
      if already_inserted.nil?
        db[:influenceremails].insert(:email => email, :youtube_influencer_id => youtube_influencer_id, :source => source, :is_correct_syntax => is_correct)
      end
    end

    def self.redefine_influencer_email youtube_influencer_id
      email = nil
      all_emails = db[:influenceremails].where(:youtube_influencer_id => youtube_influencer_id).where(:is_correct_syntax => true).all
      if all_emails.count > 0
        email = all_emails.find { |_e| _e[:source] == 'business_email' }
        if email.nil?
          email = all_emails.find { |_e| _e[:source] == 'linktree' }
          if email.nil?
            email = all_emails.find { |_e| _e[:source] == 'bio' }
            if email.nil?
              email = all_emails.find { |_e| _e[:source] == 'post' }
            end
          end
        end
      end
      if email && email[:email]
        db[:youtubeinfluencers].where(id: youtube_influencer_id).update(:email => email[:email], :is_migrated => 0)
        logger.debug("Updated youtubeinfluencers #{youtube_influencer_id}")
      end
    end

    def self.process_influencer_emails data
      emails = data[:emails]
      youtube_influencer_id = data[:youtube_influencer_id]

      update_influencer_emails(emails, youtube_influencer_id)

      true
    end

    def self.update_influencer_emails emails, youtube_influencer_id
      emails = emails.uniq { |e| e[:email] }
      emails.each do |email|
        if email[:is_correct].nil?
          email[:is_correct] = YIParser::Utils.is_email_syntax_correct(email[:email])
        end
        insert_email email[:email], youtube_influencer_id, email[:source], email[:is_correct]
      end
      redefine_influencer_email(youtube_influencer_id)
    end

    def self.set_business_email_exist(data)
      user_id = data[:userid]
      row = db[:youtubeinfluencers].select(:id).where(userid: user_id).first
      if row.nil?
        logger.error('youtubeinfluencers doesn\'t exist')
        return false
      end

      db[:youtubeinfluencers].where(:id => row[:id]).update(:is_business_email_exist => data[:is_business_email_exist])

      return true
    end

  end
end
