# frozen_string_literal: true

require 'logger'

# Global Logger
module PandaLogger
  def logger
    PandaLogger.logger
  end

  def self.logger
    @logger ||= Logger.new($stderr)
  end
end
