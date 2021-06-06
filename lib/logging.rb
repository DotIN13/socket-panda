# frozen_string_literal: true

require 'logger'
require 'English'
require_relative 'constants'

# Global Logging
module PandaLogging
  include PandaConstants

  def logger
    PandaLogging.logger
  end

  def logging_prefix
    return 'New user' unless name && id

    "#{name}/#{id[4..12]}"
  end

  def production?
    PandaLogging.production?
  end

  def log_memory
    PandaLogging.logger.debug format('%.1fMB used', `ps -o rss= -p #{$PID}`.to_f / 1024)
  end

  class << self
    def logger
      @logger ||= new_logger
    end

    def new_logger
      File.delete('panda.log') if File.exist?('panda.log')
      # logdev = production? ? $stderr : 'panda.log'
      logdev = $stderr
      level = production? ? Logger::WARN : Logger::DEBUG
      @logger = Logger.new logdev, progname: 'Socket Panda', level: level
    end

    # Default to development
    def production?
      ENV['PANDA_ENV'] == 'production'
    end
  end
end
