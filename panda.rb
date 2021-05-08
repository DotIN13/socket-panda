require 'websocket'
require 'socket'
require_relative 'lib/hall'
require_relative 'lib/wsframe'

# WSServer
class Server
  attr_reader :server, :ssl_server, :hall

  def initialize
    @server = TCPServer.new 5613
    @hall = Hall.new
    warn '[INFO] Server is running'
    start
  end

  # WIP: Should close socket if not ws connection
  def start
    loop do
      Thread.start(server.accept) do |socket|
        warn '[INFO] Incomming request'
        if socket.shake
          socket.hall = hall
          socket.write(socket.make_frame("PUT #{socket.room}"))
          socket.hold
        else
          socket.close
        end
      end
    end
  end
end

# Extend Ruby TCPSocket class
class TCPSocket
  attr_accessor :handshake, :http_request, :room, :closed, :frame
  attr_reader :hall

  def close
    super
    @closed = true
    warn '[WARN] Socket closed'
  end

  def parse_http_request
    self.http_request = ''
    # Always get line before breaking from loop
    # For HTTP request must end with "\r\n"
    loop do
      line = read_line
      return false unless line

      self.http_request += line
      break if line == "\r\n"
    end
    warn '[INFO] Received http request: ', http_request
    true
  end

  def read_line
    ready = IO.select [self], nil, nil, 3
    unless ready
      warn '[ERROR] Socket timeout'
      return false
    end
    ready.first.first.gets
  end

  def create_handshake
    self.handshake = WebSocket::Handshake::Server.new(secure: true)
    handshake << http_request
  end

  def shake
    return false unless parse_http_request

    create_handshake
    if handshake.valid?
      warn "[INFO] Handshake valid, responding with #{handshake}"
      puts handshake.to_s
    else
      warn '[ERROR] Handshake invalid, closing socket'
      return false
    end
    @closed = false
    true
  end

  def hall=(hall)
    @hall = hall
    hall.checkin(self)
  end

  def make_frame(data)
    WebSocket::Frame::Outgoing::Server.new version: handshake.version, data: data, type: :text
  end

  def hold
    until closed
      loop do
        # Get frames
        @frame = WSFrame.new(self)
        warn "[INFO] Parsed payload \"#{text = frame.parse_text}\""
        next if detect_room_change(text)

        broadcast_frame(text)
      end
    end
  end

  def detect_room_change(text)
    hall.checkin(self, text.split(' ').last) if text.start_with?('PUT')
  end

  def broadcast_frame(text)
    return unless (peer = (hall[room] - [self]).first)

    peer.write make_frame(text)
    warn "[INFO] Broadcasted payload to #{peer}"
  end
end

Server.new
