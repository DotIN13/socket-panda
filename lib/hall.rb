# frozen_string_literal: true

require 'securerandom'
require_relative 'exeption'
require_relative 'panda_logger'
require_relative 'wsframe'

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
    guests.delete guest
  end
end
