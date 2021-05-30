# frozen_string_literal: true

require_relative 'panda_logging'

# Error handling
class PandaSocketError < StandardError
  include PandaLogging

  def initialize(msg)
    logger.error msg.to_s
    super msg
  end
end

class FrameError < PandaSocketError
end

class HandshakeError < PandaSocketError
end

class SocketTimeout < PandaSocketError
end

class TalkRoomError < PandaSocketError
end

class RoomFullError < TalkRoomError
end
