require 'websocket'
require 'socket'
require 'securerandom'

# WSServer
class Server
  attr_reader :server, :ssl_server, :hall

  def initialize
    @server = TCPServer.new 5613
    @hall = Hall.new
    warn '[INFO] Server is running'
    start
  end

  # WIP: Should close socket if not ws connection
  def start
    loop do
      Thread.start(server.accept) do |socket|
        warn '[INFO] Incomming request'
        if socket.shake
          hall.checkin(socket)
          socket.write(socket.make_frame(socket.room))
          socket.hold
        else
          socket.close
        end
      end
    end
  end
end

# Extend Ruby TCPSocket class
class TCPSocket
  attr_accessor :handshake, :http_request, :room, :closed

  def close
    super
    @closed = true
    warn '[WARN] Socket closed'
  end

  def parse_http_request
    self.http_request = ''
    # Always get line before breaking from loop
    # For HTTP request must end with "\r\n"
    loop do
      line = read_line
      return false unless line

      self.http_request += line
      break if line == "\r\n"
    end
    warn '[INFO] Received http request: ', http_request
    true
  end

  def read_line
    ready = IO.select [self], nil, nil, 3
    unless ready
      warn '[ERROR] Socket timeout'
      return false
    end
    ready.first.first.gets
  end

  def create_handshake
    self.handshake = WebSocket::Handshake::Server.new(secure: true)
    handshake << http_request
  end

  def shake
    return false unless parse_http_request

    create_handshake
    if handshake.valid?
      warn "[INFO] Handshake valid, responding with #{handshake}"
      puts handshake.to_s
    else
      warn '[ERROR] Handshake invalid, closing socket'
      return false
    end
    @closed = false
    true
  end

  def make_frame(data)
    WebSocket::Frame::Outgoing::Server.new version: handshake.version, data: data, type: :text
  end

  def hold
    until closed
      loop do
        # Get frames
        frame = WSFrame.new(self)
        warn frame.parse_text
      end
    end
  end
end

class WSFrame
  attr_accessor :socket, :bytes, :payload, :payload_size, :is_masked, :mask

  def initialize(socket)
    @socket = socket
    @bytes = []
    @payload = []
    parse_info
    parse_size
    parse_mask
    gather_payload
  end

  def parse_info
    bytes << socket.getbyte
    @fin = bytes[0] & 0b10000000
    @opcode = bytes[0] & 0b00001111
    raise "We don't support continuations" unless @fin
    raise 'We only support opcode 1' unless @opcode == 1
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
  end

  def parse_text
    if is_masked
      payload.each_with_index { |byte, i| payload[i] = byte ^ mask[i % 4] }
      warn "[INFO] Unmasked payload #{payload}"
    end
    payload.pack('C*').force_encoding('utf-8').inspect
  end
end

# Talkroom
class Hall < Hash
  def checkin(guest, room = nil)
    room ||= new_room
    self[room] ||= []
    self[room] << guest
    guest.room = room
    warn "[INFO] Guest joined room ##{room} with #{self[room]}"
  end

  def new_room
    number = SecureRandom.alphanumeric.to_sym
    return number unless self[number]

    new_room
  end
end

Server.new
