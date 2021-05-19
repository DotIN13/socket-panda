# frozen_string_literal: true

require 'websocket'
require 'socket'
require_relative 'lib/hall'
require_relative 'lib/wsframe'
require_relative 'lib/exeption'
require_relative 'lib/panda_logger'
require_relative 'lib/constant'

# WSServer
class Server
  include PandaLogger
  attr_reader :server, :hall

  def initialize
    @server = TCPServer.new 5613
    @hall = Hall.new
    start
  end

  # WIP: Should close socket if not ws connection
  def start
    logger.info 'Server is running'
    loop do
      Thread.start(server.accept) do |socket|
        logger.info 'Incomming request'
        if socket.shake
          socket.hall = hall
          socket.hold
        end
      end
    end
  end
end

# Extend Ruby TCPSocket class
class TCPSocket
  include PandaLogger
  include PandaConstants
  attr_accessor :handshake, :http_request, :room, :opened
  attr_reader :hall, :msg_type, :name

  def close
    signal_close
    super
    @opened = false
    checkout
    logger.warn 'Socket closed'
  end

  def signal_close
    logger.warn 'Closing socket with closing frame'
    write WebSocket::Frame::Outgoing::Server.new version: handshake.version, type: :close
  rescue Errno::EPIPE
    logger.warn 'Broken pipe, no closing frames sent'
  rescue IOError
    logger.warn 'Closed stream, no closing frames sent'
  end

  def shake
    begin
      parse_http_request
      raise HandshakeError, 'Handshake invalid, closing socket' unless create_handshake
    rescue HandshakeError
      return close
    end

    logger.info "Handshake valid, responding with #{handshake}"
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
    close
  end

  # Talkroom methods
  def checkout
    if hall[room]
      hall[room].checkout(self)
      logger.warn "Guest left room ##{room}"
    end
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

    logger.info "Received HTTP request: #{http_request}"
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
      @data = ''
      recvmsg.lazy.each_with_index { |frame, index| handle_frame(frame, index) }
      execute_commands
    end
  end

  # Receive full message
  # Until finish
  def recvmsg
    # New enumerator per message
    Enumerator.new do |buffer|
      logger.info 'Listening for messages'
      loop do
        # Get frames
        frame = WSFrame.new
        frame.socket = self
        begin
          buffer << frame.receive
        rescue FrameError
          break close
        end
        break if frame.fin?
      end
      logger.info 'Message end'
    end
  end

  def handle_frame(frame, index)
    if index.zero?
      self.msg_type = frame.type
      # PEND filename if binary
      broadcast_frame WSFrame.new(fin: 1, opcode: 1, payload: "PEND #{frame.filename}") if msg_type == :binary
    end
    # Concat payload if frame is text and starts with commands
    @data += frame.payload if COMMANDS.include? msg_type
    # Directly forward frames nonetheless
    broadcast_frame(frame) unless msg_type == :ROOM
  end

  # Command detection and distribution
  def execute_commands
    return close if msg_type == :close

    pong if msg_type == :ping
    handle_name if msg_type == :NAME
    change_room if msg_type == :ROOM
  end

  def msg_type=(type)
    @msg_type = type
    logger.info "Received #{msg_type} frame"
  end

  def pong
    logger.info 'Responding ping with a pong'
    write WebSocket::Frame::Outgoing::Server.new version: handshake.version, data: @data, type: :pong
  end

  def change_room
    hall.checkin(self, @data[5..])
  end

  def handle_name
    @name = @data[5..]
  end

  def broadcast_frame(frame)
    return unless roommate

    roommate.write frame.prepare
    logger.info "Broadcasted frame to #{roommate}"
  end

  # Talkroom methods
  def roommate
    (hall[room].guests - [self]).first
  end
end

Server.new
