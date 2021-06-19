# frozen_string_literal: true

module PandaConstants
  COMMANDS = %i[ROOM CLIP NAME PING].freeze
  LOG = 'panda.log'
  # When receiving payload, read FRAGMENT size each time
  FRAGMENT = 4096
  ORIGINS = %w[https://localhost:4000 https://www.wannaexpresso.com].freeze
end
