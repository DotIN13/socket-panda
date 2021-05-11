# frozen_string_literal: true

require 'securerandom'
require_relative 'exeption'
require_relative 'panda_logger'

# Talkroom
class Hall < Hash
  include PandaLogger

  # room should be symbol
  def checkin(guest, room = nil)
    guest.checkout
    room = room ? room.to_sym : new_room
    self[room] ||= Room.new(room)
    begin
      raise NoRoomError, "No room available with id ##{room}" unless self[room]

      self[room] << guest
    rescue TalkRoomError
      room = new_room
      self[room] = Room.new(room)
      retry
    end
    guest.room = room
    logger.info "Guest joined room ##{room} with #{self[room].guests}"
  end

  def new_room
    number = SecureRandom.alphanumeric.to_sym
    return number unless self[number]

    new_room
  end
end

# Serve as components for the hall
# Can only be occupied by two
class Room
  attr_accessor :guests, :id

  def initialize(id, host = nil)
    @id = id
    @guests = []
    self << host if host
  end

  def <<(guest)
    raise RoomFullError, "Talkroom ##{id} is full" if guests.length > 1

    guests << guest
  end

  def checkout(guest)
    guests.delete guest
  end
end
