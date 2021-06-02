# frozen_string_literal: true

require 'socket'
require_relative 'hall'
require_relative 'guest'

# WebSocket Server
class PandaServer
  include PandaLogging
  attr_reader :server, :hall

  def initialize
    # trap_int
    @server = TCPServer.new 5613
    @hall = Hall.new
    start
  end

  def trap_int
    trap 'SIGINT' do
      warn 'Exiting'
      exit 130
    end
  end

  # WIP: Should close socket if not ws connection
  def start
    logger.info 'Server is running'
    loop do
      Thread.start(server.accept) do |socket|
        logger.info 'Incomming request'
        if socket.shake
          socket.hall = hall
          socket.listen_for_msg
        end
      end
    end
  end
end
