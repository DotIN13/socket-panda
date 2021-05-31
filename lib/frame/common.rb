# frozen_string_literal: true

require_relative '../panda_logging'
require_relative '../exeption'
require_relative '../constant'

# General namespace for WebSocket frames
module PandaFrame
  # General methods
  class Common
    include PandaLogging
    include PandaConstants
    attr_accessor :payload, :initial_size, :payload_size, :is_masked, :mask, :opcode, :fin

    def initialize; end

    # Prepare frame for sending
    # Applies to both frame forwarding and frame generation
    def prepare
      data = [(fin << 7) + opcode].pack('C')
      data << prepare_size
      data << payload
    end

    def prepare_size
      if payload_size > 2**16 - 1
        [127, payload_size].pack('CQ>')
      elsif payload_size > 125
        [126, payload_size].pack('CS>')
      else
        [payload_size].pack('C')
      end
    end

    def send(dest)
      # return logger.error('No destination sockets available') unless dest
      raise StandardError, 'No destination sockets available' unless dest

      dest.write prepare
    end

    def ping?
      @opcode == 0x09
    end

    def binary?
      @opcode == 0x02
    end

    def fin?
      @fin == 0x01
    end

    def text?
      @opcode == 0x01
    end

    def close?
      @opcode == 0x08
    end

    def command_type
      return unless text?
      return @command_type if @command_type

      COMMANDS.each do |cmd|
        @command_type = cmd if payload.start_with? cmd.to_s
      end
      @command_type
    end

    def type
      return @command_type if command_type
      return :text if text?
      return :binary if binary?
      return :close if close?
      return :ping if ping?
    end
  end
end
