# frozen_string_literal: true

require 'oj'

module YIParser
  class LinktreePossibleEmailsImport
    @config = O14::Config.get_config
    @linktree_exchange = O14::RMQ.get_channel.direct(@config.infrastructure['linktree_exchange'], durable: true)

    def self.logger
      O14::ProjectLogger.get_logger
    end

    def self.db
      O14::DB.get_db
    end

    def self.run
      db[:InfluencerLinktreeProfiles].where(possible_email: 1).all.each do |linktree_row|
        userid = db[:YouTubeInfluencers].select(:userid).where(id: linktree_row[:youtube_influencer_id]).first[:userid]
        if userid && linktree_row[:nickname]
          msg = {
            type: 'profile',
            data: {
              nickname: linktree_row[:nickname],
              userid: userid
            }
          }
          O14::RMQ.send_message @linktree_exchange, msg
        else
          logger.warn "incorrect data #{linktree_row}"
        end
      end
    end
  end
end
