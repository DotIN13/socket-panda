# Parse Websocket frames
class WSFrame
  attr_accessor :socket, :bytes, :payload, :payload_size, :is_masked, :mask, :opcode

  def initialize(socket)
    warn '[INFO] Awaiting incoming frame'
    @socket = socket
    @bytes = []
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
    @opcode = socket.opcode if @opcode.zero?
    warn "[INFO] Reveived frame with opcode #{@opcode} and fin #{@fin}"
    warn '[WARN] Received closing frame' if @opcode == 0x08
    raise FrameError, 'Opcode unsupported' unless [0x01, 0x02, 0x08].include? @opcode
  end

  def parse_size
    # Read the next bytes containing mask option and initial payload length
    bytes << socket.getbyte
    @is_masked = bytes[1] & 0b10000000
    warn "[INFO] Payload is #{is_masked ? 'masked' : 'not masked'}"
    self.payload_size = bytes[1] & 0b01111111
    warn "[INFO] Initial payload size #{payload_size}"
    # Handle extended payload length
    handle_extended_length(payload_size) if payload_size > 125
    warn "[INFO] Received frame of size #{payload_size}"
  end

  def handle_extended_length(initial_size)
    raise 'Incorrect payload size' if initial_size > 127

    self.payload_size = socket.read(2).unpack1('S>') if initial_size == 126
    self.payload_size = socket.read(8).unpack1('Q>') if initial_size == 127
  end

  def parse_mask
    return unless is_masked

    # Do not include mask in bytes
    @mask = 4.times.map { socket.getbyte }
    warn "[INFO] Parsed mask #{mask}"
  end

  def gather_payload
    self.payload = socket.read(payload_size).unpack('C*')
    warn "[INFO] Received raw payload #{payload.first(20)}..."
    payload.length
  end

  # Record @unmasked state to avoid unmasking multiple times
  def unmask
    return payload unless is_masked && !@unmasked

    payload.each_with_index { |byte, i| payload[i] = byte ^ mask[i % 4] }
    warn "[INFO] Unmasked payload #{payload.first(20)}..."
    @unmasked = true
    payload
  end

  def parse_text
    unmask.pack('C*').force_encoding('utf-8')
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

  def type
    return :text if @opcode == 0x01
    return :binary if @opcode == 0x02
    return :close if @opcode == 0x08
    return :ping if @opcode == 0x09
  end
end
