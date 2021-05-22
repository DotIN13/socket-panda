# frozen_string_literal: true

require 'securerandom'
require 'set'
require_relative 'exeption'
require_relative 'panda_logger'
require_relative 'wsframe'

# Talkroom
class Hall
  include PandaLogger
  attr_reader :rooms, :guests

  def initialize
    @rooms = {}
    @guests = Set.new
  end

  # room should be symbol
  def checkin(guest, room = nil)
    guest.checkout
    room = room ? room.to_sym : new_room
    rooms[room] ||= Room.new(room)
    begin
      raise NoRoomError, "No room available with id ##{room}" unless rooms[room]

      rooms[room] << guest
    rescue TalkRoomError
      room = new_room
      rooms[room] = Room.new(room)
      retry
    end
    guest.room = room
    logger.info "#{guest.name || 'Guest'} joined room ##{room} with #{guest.roommate&.name || 'himself'}"
  end

  def new_room
    number = SecureRandom.alphanumeric.to_sym
    return number unless rooms[number]

    new_room
  end
end

# Serve as components for the hall
# Can only be occupied by two
class Room
  include PandaLogger
  attr_accessor :guests, :id

  def initialize(id, host = nil)
    @id = id
    @guests = []
    self << host if host
  end

  def <<(guest)
    raise RoomFullError, "Talkroom ##{id} is full" if guests.length > 1

    guests << guest
    notify
  end

  def notify
    guests.last.write WSFrame.new(fin: 1, opcode: 1, payload: "ROOM #{id}").prepare
    return unless guests.length == 2

    # Notify both party of their names
    guests.first.write WSFrame.new(fin: 1, opcode: 1, payload: "PEER #{guests.last.name}").prepare
    guests.last.write WSFrame.new(fin: 1, opcode: 1, payload: "PEER #{guests.first.name}").prepare
  end

  def checkout(guest)
    logger.warn "Guest #{guest.name} left room ##{id}"
    guest.roommate&.write WSFrame.new(fin: 1, opcode: 1, payload: "POUT #{guest.name}").prepare
    guests.delete guest
  end
end
