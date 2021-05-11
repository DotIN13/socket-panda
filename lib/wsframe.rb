# Parse Websocket frames
class WSFrame
  attr_accessor :socket, :bytes, :payload, :payload_size, :is_masked, :mask

  def initialize(socket)
    warn '[INFO] Awaiting incoming frame'
    @socket = socket
    @bytes = []
    @payload = []
  end

  def receive
    parse_info
    return false if @opcode == 0x08

    parse_size
    parse_mask
    gather_payload
  end

  def parse_info
    bytes << socket.getbyte
    @fin = bytes[0][7]
    @opcode = bytes[0][0..3]
    warn "[INFO] Reveived frame with opcode #{@opcode} and fin #{@fin}"
    warn '[WARN] Received closing frame' if @opcode == 0x08
    raise FrameError, "We don't support continuations" if @fin.zero?
    raise FrameError, 'Opcode unsupported' unless [0x01, 0x08].include? @opcode
  end

  def parse_size
    # Read the next bytes containing mask option and initial payload length
    bytes << socket.getbyte
    @is_masked = bytes[1] & 0b10000000
    warn "[INFO] Payload is #{is_masked ? 'masked' : 'not masked'}"
    self.payload_size = bytes[1] & 0b01111111
    # Handle extended payload length
    handle_extended_length(payload_size) if payload_size > 125
    warn "[INFO] Received frame of size #{payload_size}"
  end

  def handle_extended_length(initial_size)
    raise 'Incorrect payload size' if initial_size > 127

    extend_length = 2 if initial_size == 126
    extend_length = 8 if initial_size == 127
    extend_length.times.map { bytes << socket.getbyte }
    self.payload_size = bytes[2..].join.to_i(10)
  end

  def parse_mask
    return unless is_masked

    # Do not include mask in bytes
    @mask = 4.times.map { socket.getbyte }
    warn "[INFO] Parsed mask #{mask}"
  end

  def gather_payload
    payload_size.times { payload << socket.getbyte }
    warn "[INFO] Received raw payload #{payload}"
    payload.length
  end

  def parse_text
    if is_masked
      payload.each_with_index { |byte, i| payload[i] = byte ^ mask[i % 4] }
      warn "[INFO] Unmasked payload #{payload}"
    end
    payload.pack('C*').force_encoding('utf-8')
  end

  def is_ping?
    @opcode == 0x09
  end
end
