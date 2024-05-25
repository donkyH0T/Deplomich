# frozen_string_literal: true

module YIParser
  autoload :ProfileCrawler,                 'profile_crawler'
  autoload :ProfileImporter,                'profile_importer'
  autoload :ProfileAgent,                   'profile_agent'
  autoload :ExportAgent,                    'export_agent'
  autoload :VideoProcessAgent,              'video_process_agent'
  autoload :HttpClient,                     'http_client'
  autoload :S3Agent,                        's3/s3_agent'
  autoload :Utils,                          'utils'
  autoload :ProxiesManager,                 'proxies_manager'
  autoload :Stat,                           'stat'
  autoload :HashtagsCounting,               'hashtags/hashtags_counting'
  autoload :HashtagsQueueFiller,            'hashtags/hashtags_queue_filler'
  autoload :HashtagsAgent,                  'hashtags/hashtags_agent'
  autoload :UpdateInfluencersFiller,        'update_influencers_filler'
  autoload :LinktreeHttpClient,             'linktree/linktree_http_client'
  autoload :LinktreeProfileAgent,           'linktree/linktree_profile_agent'
  autoload :LinktreePossibleEmailsImport,   'linktree/linktree_possible_emails_import'
  autoload :BusinessEmailsImport,           'business_emails/business_emails_import'
  autoload :BusinessEmailsAgent,            'business_emails/business_emails_agent'
  autoload :LocationQueueFiller,            'locations_search/locations_queue_filler'
end
