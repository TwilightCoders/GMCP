# frozen_string_literal: true

module GMCP
  module Voice
    # Thread folders as api2thread/list numbers them. "all" is the unified
    # Messages+Calls view, which Google caps at a few hundred recent threads;
    # the narrower folders reach further back.
    FOLDERS = {
      'all'       => 1,
      'messages'  => 2,
      'calls'     => 3,
      'voicemail' => 4,
      'spam'      => 5,
      'archived'  => 6
    }.freeze

    MESSAGE_TYPES = {
      0  => 'missed',
      1  => 'received',
      2  => 'voicemail',
      7  => 'placed',
      10 => 'sms.received',
      11 => 'sms.sent',
      14 => 'placed.cancelled'
    }.freeze

    autoload :Session,       'gmcp/voice/session'
    autoload :Message,       'gmcp/voice/message'
    autoload :Conversation,  'gmcp/voice/conversation'
    autoload :Folder,        'gmcp/voice/folder'
    autoload :Tools,         'gmcp/voice/tools'
    autoload :SafariCookies, 'gmcp/voice/safari_cookies'
  end
end
