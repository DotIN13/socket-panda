require 'websocket'
require 'socket'
require_relative 'lib/hall'
require_relative 'lib/wsframe'
require_relative 'lib/exeption'

# WSServer
class Server
  attr_reader :server, :hall

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
        end
      end
    end
  end
end

# Extend Ruby TCPSocket class
class TCPSocket
  attr_accessor :handshake, :http_request, :room, :opened, :frame
  attr_reader :hall

  def close
    super
    @opened = false
    hall[room] -= [self] if room
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
    raise HandshakeError, 'Invalid websocket request' unless http_request.downcase.include? 'upgrade: websocket'

    warn '[INFO] Received HTTP request: ', http_request
  end

  def read_line
    ready = IO.select [self], nil, nil, 3
    raise HandshakeError, 'HTTP request timeout' unless ready

    ready.first.first.gets
  end

  def create_handshake
    self.handshake = WebSocket::Handshake::Server.new(secure: true)
    handshake << http_request
    handshake.valid?
  end

  def shake
    begin
      parse_http_request
      raise HandshakeError, 'Handshake invalid, closing socket' unless create_handshake
    rescue HandshakeError
      return close
    end

    warn "[INFO] Handshake valid, responding with #{handshake}"
    puts handshake.to_s
    @opened = true
  end

  def hall=(hall)
    @hall = hall
    hall.checkin(self)
  end

  def make_frame(data)
    WebSocket::Frame::Outgoing::Server.new version: handshake.version, data: data, type: :text
  end

  def hold
    recvframe
    # Close socket
    warn '[WARN] Responding with closing frame, closing socket'
    write WebSocket::Frame::Outgoing::Server.new version: handshake.version, type: :close
    close
  end

  def recvframe
    while opened
      # Get frames
      @frame = WSFrame.new(self)
      begin
        break unless @frame.receive
      rescue FrameError
        break
      end
      warn "[INFO] Parsed payload \"#{@text = frame.parse_text}\""
      next if detect_room_change

      broadcast_frame
    end
  end

  def detect_room_change
    hall.checkin(self, @text.split(' ').last) if @text.start_with?('PUT')
  end

  def broadcast_frame
    return unless roommate

    roommate.write make_frame(@text)
    warn "[INFO] Broadcasted payload to #{roommate}"
  end

  # Talkroom methods
  def checkout
    hall[room].checkout(self) if room
  end

  def roommate
    (hall[room].guests - [self]).first
  end
end

Server.new
