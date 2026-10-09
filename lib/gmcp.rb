require 'pathname'
require 'base64'
require 'fileutils'
require 'him'

require_relative 'gmcp/version'

module GMCP
  def self.root(*args)
    (@root ||= Pathname.new(File.expand_path('../', __dir__))).join(*args)
  end

  autoload :Auth,             'gmcp/auth'
  autoload :ApiError,         'gmcp/api_error'
  autoload :BearerMiddleware, 'gmcp/bearer_middleware'
  autoload :Apis,             'gmcp/apis'
  autoload :ApiBinding,       'gmcp/api_binding'
  autoload :AccountRegistry,  'gmcp/account_registry'
  autoload :Capabilities,     'gmcp/capabilities'
  autoload :ToolHelpers,      'gmcp/tool_helpers'
  autoload :Server,           'gmcp/server'
  autoload :Voice,            'gmcp/voice'

  module Gmail
    autoload :Message, 'gmcp/gmail/message'
    autoload :Label,   'gmcp/gmail/label'
    autoload :Mime,    'gmcp/gmail/mime'
    autoload :Draft,   'gmcp/gmail/draft'
    autoload :Unsubscribe, 'gmcp/gmail/unsubscribe'
    autoload :Tools,   'gmcp/gmail/tools'
  end

  module Calendar
    autoload :Event,    'gmcp/calendar/event'
    autoload :Calendar, 'gmcp/calendar/calendar'
    autoload :Tools,    'gmcp/calendar/tools'
  end

  module Drive
    autoload :File,  'gmcp/drive/file'
    autoload :Tools, 'gmcp/drive/tools'
  end
end
