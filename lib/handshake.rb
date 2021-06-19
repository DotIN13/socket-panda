# frozen_string_literal: true

require 'digest/sha1'
require_relative 'constants'
require_relative 'exeption'
require_relative 'logging'

class SocketPanda
  class Handshake
    include PandaLogging
    include PandaConstants
    attr_accessor :request, :http_version, :socket

    def initialize(socket)
      self.socket = socket
      self.request = Struct.new('Headers', :http_method, :http_version, :Origin, :Upgrade, :Connection,
                                :"Sec-WebSocket-Key", :"Sec-WebSocket-Version").new
      read_http_request
      respond
    end

    # WIP: should send 400 error if bad http request
    def read_http_request
      # Always get line before breaking from loop
      # For HTTP request must end with "\r\n"
      read_first_line
      read_headers
      logger.info "Received valid WebSocket request #{request}"
      raise HandshakeError, 'Invalid HTTP request type' unless valid_type?
      raise HandshakeError, 'Invalid WebSocket request' unless valid_headers?
    end

    private

    # Read and validate first line of HTTP request
    def read_first_line
      first_line = on_socket_ready.gets
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
      until (line = on_socket_ready.gets) == "\r\n"
        pair = line.split(': ', 2)
        request[pair.first] = pair.last.chomp
      end
    rescue NameError
      retry
    end

    def valid_headers?
      valid = []
      valid << (ORIGINS.include? request[:Origin])
      valid << (request[:Upgrade] == 'websocket')
      valid << (request[:Connection] == 'Upgrade')
      valid << (request[:'Sec-WebSocket-Version'] == '13')
      valid.all? true
    end

    # Socket methods
    def on_socket_ready(timeout = 3)
      ready = IO.select [socket], nil, nil, timeout
      raise SocketTimeout, 'Socket read timeout' unless ready

      socket
    end

    # Generate response
    def respond
      response_key = Digest::SHA1.base64digest [request[:'Sec-WebSocket-Key'],
                                                '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'].join
      logger.debug "Responding with WebSocket key #{response_key}"
      socket.write <<~ENDOFSTRING
        HTTP/#{http_version} 101 Switching Protocols
        Upgrade: websocket
        Connection: Upgrade
        Sec-WebSocket-Accept: #{response_key}\r\n
      ENDOFSTRING
    end
  end
end
