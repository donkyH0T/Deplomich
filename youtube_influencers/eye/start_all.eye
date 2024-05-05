eye load eye/export_agent.eye
eye load eye/hashtags_agent.eye
eye load eye/hashtags_queue_filler.eye
eye load eye/linktree_profile_agent.eye
eye load eye/profile_agent.eye
eye load eye/s3_agent.eye
eye load eye/update_influencers_filler.eye
eye load eye/video_agent.eye
eye load eye/business_emails_import.eye


eye start yi_parser.export_agent
eye start yi_parser.hashtags_agent
eye start yi_parser.business_emails_import
eye start yi_parser.hashtags_queue_filler
eye start yi_parser.linktree_profile_agent
eye start yi_parser.profile_agent
eye start yi_parser.s3_agent
eye start yi_parser.update_influencers_filler
eye start yi_parser.video_agent