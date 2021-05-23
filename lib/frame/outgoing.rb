# frozen_string_literal: true

require_relative 'common'

module PandaFrame
  # Outgoing frames
  class Outgoing < Common
    def initialize(opts = { payload: '', fin: 1, opcode: 1 })
      super()
      self.payload = opts[:payload] if opts[:payload]
      self.opcode = opts[:opcode] if opts[:opcode]
      self.fin = opts[:fin] if opts[:fin]
      self.payload_size = payload.bytesize if payload
    end
  end

  # Build outgoing text frames easier
  class OutgoingText < Outgoing
    def initialize(payload)
      super payload: payload, fin: 1, opcode: 1
    end
  end
end
