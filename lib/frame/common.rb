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

    def deliver(dest)
      return logger.error('No destination sockets available') unless dest&.opened

      # Send frame if target socket is not busy
      # or is busy from the same message source.
      # Queue frame if otherwise
      if dest.busy_from == source || !dest.busy_from
        send_frame(dest)
      else
        queue_frame
      end
    end

    def send_frame(dest)
      dest.write prepare
      logger.info 'Sent frame'
      # Set #busy_from only when socket is not busy
      # or when busy from the same message source
      # to make sure message from other source
      # do not mess with busy_from
      dest.busy_from = fin? ? nil : source
      # Unload queued message one by one instead of all at once
      dest.unload_queue if fin?
    end

    def queue_frame
      dest.queue(self)
      logger.info 'Target socket is blocked, queued frame'
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

    def source
      return :forwarded if instance_of? PandaFrame::Incomming

      :outgoing
    end
  end
end
