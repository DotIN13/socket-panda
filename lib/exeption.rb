# Error handling
class PandaSocketError < StandardError
  def initialize(msg)
    warn "[ERROR] #{msg}"
    super msg
  end
end

class FrameError < PandaSocketError
end

class HandshakeError < PandaSocketError
end
