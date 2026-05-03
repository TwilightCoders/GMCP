# frozen_string_literal: true

module GMCP
  module Voice
    BASE_URL        = 'https://www.google.com/voice/b/0/'.freeze
    OAUTH_LOGIN_URL = 'https://accounts.google.com/OAuthLogin'.freeze

    FEEDS = %w[inbox starred all spam trash voicemail sms recorded placed received missed].freeze

    FEED_URLS = FEEDS.each_with_object({}) do |name, h|
      h[name.to_sym] = "#{BASE_URL}inbox/recent/#{name}/"
    end.freeze

    SEARCH_URL   = "#{BASE_URL}inbox/search/".freeze
    DOWNLOAD_URL = "#{BASE_URL}media/send_voicemail/".freeze

    OPERATION_URLS = {
      delete:  "#{BASE_URL}inbox/deleteMessages/",
      archive: "#{BASE_URL}inbox/archiveMessages/",
      mark:    "#{BASE_URL}inbox/mark/",
      star:    "#{BASE_URL}inbox/star/",
      sms:     "#{BASE_URL}sms/send/",
    }.freeze

    MESSAGE_TYPES = {
      0  => 'missed',
      1  => 'received',
      2  => 'voicemail',
      4  => 'recorded',
      7  => 'placed',
      10 => 'sms.received',
      11 => 'sms.sent',
    }.freeze

    autoload :Session,       'gmcp/voice/session'
    autoload :Message,       'gmcp/voice/message'
    autoload :Folder,        'gmcp/voice/folder'
    autoload :Tools,         'gmcp/voice/tools'
    autoload :SafariCookies, 'gmcp/voice/safari_cookies'
  end
end
