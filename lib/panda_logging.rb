# frozen_string_literal: true

require 'logger'

# Global Logging
module PandaLogging
  def logger
    PandaLogging.logger
  end

  def logging_prefix
    return 'New user' unless name && id

    "#{name}/#{id[4..12]}"
  end

  class << self
    def logger
      @logger ||= new_logger
    end

    def new_logger
      logdev = production? ? $stderr : 'panda.log'
      level = production? ? Logger::WARN : Logger::DEBUG
      @logger = Logger.new logdev, progname: 'Socket Panda', level: level
    end

    # Default to development
    def production?
      ENV['PANDA_ENV'] == 'production'
    end
  end
end
