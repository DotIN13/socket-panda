# frozen_string_literal: true

require 'websocket'
require 'socket'
require_relative 'lib/hall'
require_relative 'lib/frame'
require_relative 'lib/exeption'
require_relative 'lib/panda_logging'
require_relative 'lib/constant'

# WSServer
class Server
  include PandaLogging
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
          socket.listen_for_msg
        end
      end
    end
  end
end

# Extend Ruby TCPSocket class
class TCPSocket
  include PandaLogging
  include PandaConstants
  attr_accessor :hall, :room, :handshake, :http_request, :msg_type, :opened
  attr_reader :name, :id

  def close
    signal_close
    super
    @opened = false
    checkout
    logger.warn(logging_prefix) { 'Socket closed' }
  end

  def shake
    begin
      parse_http_request
      raise HandshakeError, 'Handshake invalid, closing socket' unless create_handshake
    rescue HandshakeError
      return close
    end

    logger.info(logging_prefix) { "Handshake valid, responding with #{handshake}" }
    puts handshake.to_s
    @opened = true
  end

  def read_on_ready(timeout = 3)
    ready = IO.select [self], nil, nil, timeout
    raise SocketTimeout, 'Socket read timeout' unless ready

    yield ready.first.first
  end

  def listen_for_msg
    recvmsg
    # Close socket if closing frame received or an error occured
    close
  rescue IOError => e
    logger.warn(logging_prefix) { e.message.capitalize }
  rescue SocketTimeout, FrameError
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

    logger.info(logging_prefix) { "Received HTTP request: #{http_request}" }
  end

  def create_handshake
    self.handshake = WebSocket::Handshake::Server.new(secure: true)
    handshake << http_request
    handshake.valid?
  end

  # Main receiving method
  def recvmsg
    while opened
      @data = String.new
      # Receive the rest if not finished
      recv_the_rest unless recv_first_frame
      execute_commands
    end
  end

  # Receive the first frame to decide if following frames should be stored
  # Return true if finished
  def recv_first_frame
    logger.info(logging_prefix) { 'Listening for first frame' }
    handle_first_frame recvframe
  end

  # Set msg_type on receiving first frame
  # To decide how following frames should be processed
  def handle_first_frame(frame)
    self.msg_type = frame.type
    logger.info(logging_prefix) { "Received #{msg_type} frame" }
    # PEND filename if binary, assuming all binary frames were parts of a file
    broadcast_frame PandaFrame::OutgoingText.new("PEND #{frame.filename}") if msg_type == :binary
    # Also handle the first frame as a general frame
    handle_frame frame
  end

  # Receive a single frame
  def recvframe
    frame = PandaFrame::Incomming.new self
    # If FrameError is raised, rescue in #hold and close the connection
    frame.receive
  end

  # Receive full messages
  # Until finish
  def recv_the_rest
    logger.info(logging_prefix) { 'Receiving remaining frames for the current message' }
    loop do
      break if handle_frame recvframe
    end
    logger.info(logging_prefix) { 'Message end' }
  end

  # Return true if message is finished
  def handle_frame(frame)
    # Concat payload only if frame is text and starts with commands
    @data << frame.payload if COMMANDS.include? msg_type
    # Directly forward frames nonetheless
    broadcast_frame(frame) unless %i[ROOM PING NAME ping close].include? msg_type
    frame.fin?
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

  def pong
    logger.info(logging_prefix) { 'Responding ping with a pong' }
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
    logger.info(logging_prefix) { 'Checking in for the first time' }
    hall.checkin(self)
  end

  def broadcast_frame(frame)
    return unless roommate

    frame.send roommate
    logger.info(logging_prefix) { 'Broadcasted frame to peer' }
  end

  def signal_close
    logger.warn(logging_prefix) { 'Closing socket with closing frame' }
    PandaFrame::Outgoing.new(fin: 1, opcode: 8, payload: 'CLOSE').send self
  rescue Errno::EPIPE
    logger.warn(logging_prefix) { 'Broken pipe, no closing frames sent' }
  rescue IOError
    logger.warn(logging_prefix) { 'Closed stream, no closing frames sent' }
  end
end

Server.new
