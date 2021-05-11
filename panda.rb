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
    start
  end

  # WIP: Should close socket if not ws connection
  def start
    warn '[INFO] Server is running'
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
  attr_reader :hall, :opcode

  def close
    super
    @opened = false
    checkout
    warn '[WARN] Socket closed'
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

  def make_frame(data, type = :text)
    WebSocket::Frame::Outgoing::Server.new version: handshake.version, data: data, type: type
  end

  def hold
    recvframe
    # Close socket if closing frame received or an error occured
    warn '[WARN] Responding with closing frame, closing socket'
    begin
      write WebSocket::Frame::Outgoing::Server.new version: handshake.version, type: :close
    rescue Errno::EPIPE
      warn '[WARN] Connection lost, no closing frames sent'
    end
    close
  end

  # Talkroom methods
  def checkout
    hall[room]&.checkout(self)
    warn "[WARN] Guest left room ##{room}"
    self.room = nil
  end

  private

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

  def recvframe
    while opened
      # Get frames
      @frame = WSFrame.new(self)
      begin
        break unless @frame.receive
      rescue FrameError
        break
      end
      handle_payload
      next if execute_commands

      broadcast_frame if frame.fin? && roommate
    end
  end

  # Command detection and distribution
  def execute_commands
    return unless frame.fin? && frame.text?

    return change_room if @data.start_with?('PUT')

    false
  end

  def handle_payload
    concat_payload
    # Store opcode if not finished
    return pong if frame.ping?
    return @opcode = frame.opcode unless frame.fin?

    # Process data
    warn "[INFO] Parsed payload \"#{@data.force_encoding('utf-8')[0..20]}...\"" if frame.text?
    # Do nothing if binary
    warn '[INFO] Received binary frame as is' if frame.binary?
  end

  def concat_payload
    @buffer ||= []
    @buffer += frame.unmask
    return unless frame.fin?

    # Update @data if finished
    @data = @buffer.pack('C*')
    # Release buffer if finished
    @buffer = []
  end

  def pong
    write WebSocket::Frame::Outgoing::Server.new version: handshake.version, data: @data, type: :pong
  end

  def change_room
    hall.checkin(self, @data.split(' ').last)
    # Respond with room change complete message
    write make_frame(@data)
    true
  end

  def broadcast_frame
    roommate.write make_frame(@data, frame.type)
    warn "[INFO] Broadcasted payload to #{roommate}"
  end

  # Talkroom methods
  def roommate
    (hall[room].guests - [self]).first
  end
end

Server.new
