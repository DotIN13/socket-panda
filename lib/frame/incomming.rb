# frozen_string_literal: true

require_relative 'common'
require_relative '../constants'

module PandaFrame
  class Incomming < Common
    include PandaConstants
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
      self
    end

    def parse_info
      first = recv_first_byte
      self.fin = first[7]
      self.opcode = first[0..3]
      logger.info "Reveived frame with opcode #{opcode} and fin #{fin}"
      raise FrameError, 'Opcode unsupported' unless [0x00, 0x01, 0x02, 0x08].include? opcode
    end

    def recv_first_byte
      ready = IO.select [socket], nil, nil, 20
      return socket.getbyte if ready

      raise SocketTimeout, 'No incomming messages in 20 seconds, socket dead'
    end

    def parse_size
      # Read the next bytes containing mask option and initial payload length
      second = socket.getbyte
      self.is_masked = second & 0b10000000
      logger.debug 'Payload is masked' if is_masked
      self.initial_size = second & 0b01111111
      logger.debug "Initial payload size #{initial_size}"
      # Handle extended payload length
      measure_payload
      logger.debug "Received frame of size #{payload_size}"
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
      @mask32 = mask.unpack('C*')
      @mask64 = (mask * 2).unpack1('Q')
      logger.debug 'Parsed frame mask'
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
      tail = payload_size % FRAGMENT
      (payload_size / FRAGMENT).times { xor socket.read(FRAGMENT) }
      xor socket.read(tail)
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
