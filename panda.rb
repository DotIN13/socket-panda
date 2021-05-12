# frozen_string_literal: true

require 'websocket'
require 'socket'
require_relative 'lib/hall'
require_relative 'lib/wsframe'
require_relative 'lib/exeption'
require_relative 'lib/panda_logger'

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
          socket.write(socket.make_frame("PUT #{socket.room}"))
          socket.hold
        end
      end
    end
  end
end

# Extend Ruby TCPSocket class
class TCPSocket
  include PandaLogger
  attr_accessor :handshake, :http_request, :room, :opened
  attr_reader :hall

  def close
    logger.warn 'Responding with closing frame, closing socket'
    begin
      write WebSocket::Frame::Outgoing::Server.new version: handshake.version, type: :close
    rescue Errno::EPIPE
      logger.warn 'Connection lost, no closing frames sent'
    end
    super
    @opened = false
    checkout
    logger.warn 'Socket closed'
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
      recvmsg.lazy.each_with_index do |frame, index|
        self.msg_type = frame.type if index.zero?
        handle_frame(frame)
      end
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

  def handle_frame(frame)
    # Concat payload if frame is text and starts with commands
    if @msg_type == :command
      @data += frame.payload
    else # Directly forward frames if frame is raw text or binary
      broadcast_frame(frame)
    end
  end

  # Command detection and distribution
  def execute_commands
    return close if @msg_type == :close

    pong if @msg_type == :ping
    change_room if @data&.start_with?('PUT') && @msg_type == :command
  end

  def msg_type=(type)
    @msg_type = type
    logger.info "Received #{@msg_type} frame"
  end

  def pong
    logger.info 'Responding ping with a pong'
    write WebSocket::Frame::Outgoing::Server.new version: handshake.version, data: @data, type: :pong
  end

  def change_room
    hall.checkin(self, @data.split(' ').last)
    # Respond with room change complete message
    write make_frame(@data)
    true
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
