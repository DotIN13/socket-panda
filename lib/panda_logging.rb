# frozen_string_literal: true

require 'logger'

# Global Logging
module PandaLogging
  def logger
    PandaLogging.logger
  end

  def prepend_identity(msg)
    name && id ? "#{name} - #{id}: #{msg}" : msg
  end

  def self.logger
    @logger ||= Logger.new($stderr)
  end
end
