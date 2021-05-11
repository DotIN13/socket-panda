# frozen_string_literal: true

require_relative 'panda_logger'

# Error handling
class PandaSocketError < StandardError
  include PandaLogger

  def initialize(msg)
    logger.error msg.to_s
    super msg
  end
end

class FrameError < PandaSocketError
end

class HandshakeError < PandaSocketError
end

class TalkRoomError < PandaSocketError
end

class RoomFullError < TalkRoomError
end
