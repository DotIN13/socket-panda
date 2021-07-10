# frozen_string_literal: true

require 'digest/sha1'
require_relative 'constants'
require_relative 'exeption'
require_relative 'logging'

class SocketPanda
  class Handshake
    include SocketPanda::Logging
    attr_accessor :request, :http_version, :socket

    def initialize(socket)
      self.socket = socket
      self.request = SocketPanda::Headers.new
      read_http_request
      respond
    end

    # WIP: should send 400 error if bad http request
    def read_http_request
      # Always get line before breaking from loop
      # For HTTP request must end with "\r\n"
      read_first_line
      read_headers
      logger.info "Received WebSocket request #{request}"
      raise HandshakeError, 'Invalid HTTP request type' unless valid_type?
      raise HandshakeError, 'Invalid WebSocket request' unless valid_headers?
    end

    private

    # Read and validate first line of HTTP request
    def read_first_line
      first_line = on_socket_readable.gets
      request[:http_method] = first_line.split(' ', 2)[0]
      request[:http_version] = first_line.match(%r{HTTP/(\d+\.?\d*)})[1]
    end

    def valid_type?
      request[:http_method] == 'GET' && valid_http_version?
    end

    def valid_http_version?
      http_version = request[:http_version].to_f
      float?(request[:http_version]) && http_version >= 1.1
    end

    def float?(str)
      str.to_f.to_s == str
    end

    # Read and validate headers
    def read_headers
      until (line = on_socket_readable.gets) == "\r\n"
        pair = line.split(': ', 2)
        request[pair.first.downcase] = pair.last.chomp
      end
    rescue NameError
      retry
    end

    def valid_headers?
      valid = []
      # Only test origin in production mode
      valid << (SocketPanda::ORIGINS.include? request[:origin]) if production?
      valid << (request[:upgrade] == 'websocket')
      valid << (request[:connection] == 'Upgrade')
      valid << (request[:'sec-websocket-version'] == '13')
      valid.all? true
    end

    # Socket methods
    def on_socket_readable(timeout = 3)
      ready = socket.wait timeout
      raise SocketTimeout, 'Socket read timeout' unless ready

      socket
    end

    # Generate response
    def respond
      response_key = Digest::SHA1.base64digest [request[:'sec-websocket-key'],
                                                '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'].join
      logger.debug "Responding with WebSocket key #{response_key}"
      socket.write <<~ENDOFSTRING
        HTTP/#{request[:http_version]} 101 Switching Protocols
        upgrade: websocket
        connection: Upgrade
        sec-websocket-accept: #{response_key}\r\n
      ENDOFSTRING
    end
  end
end
