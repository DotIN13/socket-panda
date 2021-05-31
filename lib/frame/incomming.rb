# frozen_string_literal: true

require_relative 'common'

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
      gather_payload
      unmask
      self
    end

    def parse_info
      recv_first_byte
      logger.info "Reveived frame with opcode #{opcode} and fin #{fin}"
      logger.warn 'Received closing frame' if opcode == 0x08
      raise FrameError, 'Opcode unsupported' unless [0x00, 0x01, 0x02, 0x08].include? opcode
    end

    def recv_first_byte
      first = socket.getbyte
      self.fin = first[7]
      self.opcode = first[0..3]
    end

    def parse_size
      # Read the next bytes containing mask option and initial payload length
      second = socket.getbyte
      self.is_masked = second & 0b10000000
      logger.info 'Payload is masked' if is_masked
      self.initial_size = second & 0b01111111
      logger.info "Initial payload size #{initial_size}"
      # Handle extended payload length
      measure_payload
      logger.info "Received frame of size #{payload_size}"
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
      @mask = 4.times.map { socket.read_on_ready(&:getbyte) }
      logger.info "Parsed mask #{mask}"
    end

    def gather_payload
      self.payload = socket.read_on_ready { |conn| conn.read(payload_size) }.unpack('C*')
      logger.info "Received raw payload #{payload.first(10)}..."
    end

    # Record @unmasked state to avoid unmasking multiple times
    def unmask
      return payload unless is_masked && !@unmasked

      payload.each_with_index { |byte, i| payload[i] = byte ^ mask[i % 4] }
      logger.info "Unmasked payload #{payload.first(10)}..."
      @unmasked = true
      self.payload = payload.pack('C*')
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
