# frozen_string_literal: true

require 'logger'
require 'English'
require_relative 'constants'

class SocketPanda
  class MultiIO
    def initialize(*targets)
      @targets = targets
    end

    def write(*args)
      @targets.each { |t| t.write(*args) }
    end

    def close
      @targets.each(&:close)
    end
  end

  # Global Logging
  module Logging
    def logger
      SocketPanda::Logging.logger
    end

    def logging_prefix
      return 'New user' unless name && id

      "#{name}/#{id[4..12]}"
    end

    def production?
      SocketPanda::Logging.production?
    end

    def log_memory
      SocketPanda::Logging.logger.debug format('%.1fMB used', `ps -o rss= -p #{$PID}`.to_f / 1024)
    end

    class << self
      def logger
        @logger ||= new_logger
      end

      def new_logger
        logdev = production? ? $stderr : SocketPanda::MultiIO.new($stderr, File.open('./panda.log', 'w'))
        level = production? ? Logger::WARN : Logger::DEBUG
        @logger = Logger.new logdev, progname: 'Socket Panda', level: level
      end

      # Default to development
      def production?
        ENV['PANDA_ENV'] == 'production'
      end
    end
  end
end
