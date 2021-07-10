# frozen_string_literal: true

require_relative 'common'
require_relative '../constants'

module PandaFrame
  class Incomming < Common
    attr_accessor :socket

    def initialize(socket)
      super()
      self.socket = socket
    end

    # Incoming frames
    def receive
      parse_info
      parse_size
      parse_mask
      recv_payload
      # logger.debug "Incomming payload size: #{payload.bytesize}"
      self
    end

    def parse_info
      first = recv_first_byte
      raise FrameError, 'Received nil when reading, the socket might have already been closed' if first.nil?

      self.fin = first[7]
      self.opcode = first[0..3]
      raise FrameError, 'Opcode unsupported' unless [0x00, 0x01, 0x02, 0x08].include? opcode
    end

    # Attempt to fix an error in `parse_info': undefined method `[]' for nil:NilClass (NoMethodError) after idling
    def recv_first_byte
      ready = socket.wait 20
      raise SocketTimeout, 'No incomming messages in 20 seconds, socket dead' unless ready

      socket.getbyte
    end

    def parse_size
      # Read the next bytes containing mask option and initial payload length
      second = socket.getbyte
      self.is_masked = second & 0b10000000
      self.initial_size = second & 0b01111111
      # Handle extended payload length
      measure_payload
      logger.debug "Receiving frame: opcode #{opcode}, fin #{fin}, size #{payload_size}"
    end

    def measure_payload
      raise FrameError, 'Unsupported payload size' if initial_size > 127

      self.payload_size = initial_size if initial_size < 126
      self.payload_size = socket.read(2).unpack1('S>') if initial_size == 126
      self.payload_size = socket.read(8).unpack1('Q>') if initial_size == 127
    end

    def parse_mask
      return unless is_masked

      # Do not include mask in bytes
      @mask = socket.read(4)
      # @mask32 = mask.unpack('C*')
      @mask64 = (mask * 2).unpack1('Q')
    end

    def recv_payload
      if is_masked
        recv_and_unmask
      else
        self.payload = socket.read(payload_size)
      end
    end

    def recv_and_unmask
      self.payload = String.new
      head = payload_size / SocketPanda::FRAGMENT
      tail = payload_size % SocketPanda::FRAGMENT
      # logger.debug "Payload head: #{head}, payload tail: #{tail}"
      head.times { xor socket.read(SocketPanda::FRAGMENT) }
      # Do xor another time only when there is more data in the pipeline
      xor socket.read(tail) if tail.positive?
    end

    # Record #unmasked state to avoid unmasking multiple times
    def xor(raw)
      size = raw.bytesize
      padding = 0.chr * (8 - size % 8)
      raw = (raw + padding).unpack('Q*')
      raw.each_index { |i| raw[i] ^= @mask64 }
      payload << raw.pack('Q*')[0..size - 1]
    end

    # Assuming the first byte comtains the byte length for filename
    # and the following bytes contains the filename
    def filename
      return unless binary?

      name_length = payload[0].unpack1('C')
      payload[1..name_length]
    end
  end
end
