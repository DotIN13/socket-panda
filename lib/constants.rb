# frozen_string_literal: true

class SocketPanda
  COMMANDS = %i[ROOM CLIP NAME PING PONG].freeze
  LOG = 'panda.log'
  # When receiving payload, read FRAGMENT size each time
  FRAGMENT = 4096
  ORIGINS = %w[https://localhost:4000 https://www.wannaexpresso.com].freeze
  Headers = Struct.new('Headers', :http_method, :http_version, :origin, :upgrade, :connection,
                       :"sec-websocket-key", :"sec-websocket-version")
end
