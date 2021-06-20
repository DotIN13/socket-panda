# frozen_string_literal: true

require 'socket'
require_relative 'handshake'
require_relative 'frame'
require_relative 'exeption'
require_relative 'logging'
require_relative 'constants'

# Extend Ruby TCPSocket class
class TCPSocket
  include PandaLogging
  include PandaConstants
  attr_accessor :hall, :room, :handshake, :http_request, :opened, :msg_type, :busy_from
  attr_reader :name, :id

  def close
    signal_close
    super
    @opened = false
    checkout
    logger.warn(logging_prefix) { 'Socket closed' }
  end

  def shake
    SocketPanda::Handshake.new self
    @opened = true
  rescue HandshakeError
    close
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

  def queue(msg)
    message_queue << msg
  end

  def unload_queue
    return if message_queue.empty?

    message_queue.shift.deliver self
  end

  # Talkroom methods
  def checkout
    # Checkout from previous room
    room&.checkout self
    self.room = nil
  end

  def roommate
    room&.other self
  end

  private

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
    frame = recvframe until handle_frame(frame)
    logger.info(logging_prefix) { 'Message end' }
  end

  # Return true if message is finished
  # #handle_frame is called after every received frame
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
    PandaFrame::Outgoing.new(fin: 1, opcode: res, payload: 'PONG').deliver self
  end

  def change_room
    hall.checkin self, @data[5..]
  end

  def handle_name
    @name, @id = @data[5..].split(' ')
    @id = id.to_sym
    # Remove dead connection from previous room
    # hall.remove_ghost(id)
    # Join room only after name is received
    logger.info(logging_prefix) { 'Checking in for the first time' }
    hall.checkin self
  end

  def broadcast_frame(frame)
    return unless roommate

    logger.info(logging_prefix) { 'Attempting to broadcast frame' }
    frame.deliver roommate
  end

  # Queue method
  def message_queue
    @message_queue ||= []
  end

  def signal_close
    logger.warn(logging_prefix) { 'Closing socket with closing frame' }
    PandaFrame::Outgoing.new(fin: 1, opcode: 8, payload: 'CLOSE').deliver self
  rescue Errno::EPIPE
    logger.warn(logging_prefix) { 'Broken pipe, no closing frames sent' }
  rescue IOError
    logger.warn(logging_prefix) { 'Closed stream, no closing frames sent' }
  end
end
