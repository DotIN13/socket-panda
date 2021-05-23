# frozen_string_literal: true

require 'websocket'
require 'socket'
require_relative 'lib/hall'
require_relative 'lib/frame'
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
  attr_accessor :hall, :room, :handshake, :http_request, :opened
  attr_reader :msg_type, :name, :id

  def close
    signal_close
    super
    @opened = false
    checkout
    logger.warn 'Socket closed'
  end

  def signal_close
    logger.warn 'Closing socket with closing frame'
    PandaFrame::Outgoing.new(fin: 1, opcode: 8, payload: 'CLOSE').send self
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

  def read_on_ready(timeout = 3)
    ready = IO.select [self], nil, nil, timeout
    raise SocketTimeout, 'Socket read timeout' unless ready

    yield ready.first.first
  end

  def hold
    recvframe
    # Close socket if closing frame received or an error occured
    close
  rescue IOError => e
    logger.warn e.message.capitalize
  rescue SocketTimeout
    close
  end

  # Talkroom methods
  def checkout
    # Checkout from previous room
    room&.checkout(self)
    self.room = nil
  end

  def roommate
    room&.other(self)
  end

  private

  def parse_http_request
    self.http_request = ''
    # Always get line before breaking from loop
    # For HTTP request must end with "\r\n"
    loop do
      line = read_on_ready(&:gets)
      return false unless line

      self.http_request += line
      break if line == "\r\n"
    end
    raise HandshakeError, 'Invalid websocket request' unless http_request.downcase.include? 'upgrade: websocket'

    logger.info "Received HTTP request: #{http_request}"
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
        frame = PandaFrame::Incomming.new
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
      broadcast_frame PandaFrame::OutgoingText.new("PEND #{frame.filename}") if msg_type == :binary
    end
    # Concat payload if frame is text and starts with commands
    @data += frame.payload if COMMANDS.include? msg_type
    # Directly forward frames nonetheless
    broadcast_frame(frame) unless %i[ROOM PING NAME ping close].include? msg_type
  end

  # Command detection and distribution
  def execute_commands
    case msg_type
    when :close
      close
    when :ping, :PING
      pong
    when :NAME
      handle_name
    when :ROOM
      change_room
    end
  end

  def msg_type=(type)
    @msg_type = type
    logger.info "Received #{msg_type} frame"
  end

  def pong
    logger.info 'Responding ping with a pong'
    # Respond with text pong as javascript API does not support pong frame handling
    res = msg_type == :ping ? 0x0A : 0x01
    PandaFrame::Outgoing.new(fin: 1, opcode: res, payload: 'PONG').send self
  end

  def change_room
    hall.checkin(self, @data[5..])
  end

  def handle_name
    @name, @id = @data[5..].split(' ')
    @id = id.to_sym
    # Remove dead connection from previous room
    # hall.remove_ghost(id)
    # Join room only after name is received
    logger.info "Checking in #{name} for the first time"
    hall.checkin(self)
  end

  def broadcast_frame(frame)
    return unless roommate

    frame.send roommate
    logger.info "Broadcasted frame to #{roommate.name}"
  end
end

Server.new
