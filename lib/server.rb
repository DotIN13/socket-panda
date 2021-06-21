# frozen_string_literal: true

require 'socket'
require 'evt'
require_relative 'hall'
require_relative 'guest'

# WebSocket Server
class PandaServer
  include PandaLogging
  attr_reader :server, :hall

  def initialize
    trap_int
    Fiber.set_scheduler Evt::Scheduler.new
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
    Fiber.schedule do
      loop do
        socket = server.accept
        logger.info 'Incomming request'
        Fiber.schedule do
          if socket.shake
            socket.hall = hall
            socket.listen_for_msg
          end
        end
      end
    end
  end
end
