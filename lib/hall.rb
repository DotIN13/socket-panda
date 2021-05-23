# frozen_string_literal: true

require 'securerandom'
require 'set'
require_relative 'exeption'
require_relative 'panda_logger'
require_relative 'frame'

# Talkroom
class Hall
  include PandaLogger
  attr_reader :rooms, :guests

  def initialize
    @rooms = {}
    @guests = {}
  end

  # room should be symbol
  def checkin(guest, number = nil)
    guest.checkout
    number = number ? number.to_sym : new_room_number
    rooms[number] ||= Room.new(number)
    begin
      raise NoRoomError, "No room available with id ##{number}" unless rooms[number]

      rooms[number] << guest
    rescue TalkRoomError
      number = new_room_number
      rooms[number] = Room.new(number)
      retry
    end
    guest.room = rooms[number]
    logger.info "#{guest.name || 'Guest'} joined room ##{number} with #{guest.roommate&.name || 'himself'}"
  end

  def new_room_number
    number = SecureRandom.alphanumeric.to_sym
    return number unless rooms[number]

    new_room_number
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

  def other(guest)
    return unless (index = guests.index(guest))

    guests[index - 1]
  end

  def notify
    PandaFrame::OutgoingText.new("ROOM #{id}").send guests.last
    return unless guests.length == 2

    # Notify both party of their names
    PandaFrame::OutgoingText.new("PEER #{guests.last.name}").send guests.first
    PandaFrame::OutgoingText.new("PEER #{guests.first.name}").send guests.last
  end

  def checkout(guest)
    return unless guests.delete guest

    logger.warn "Guest #{guest.name} left room ##{id}"
    PandaFrame::OutgoingText.new("POUT #{guest.name}").send guest.roommate
  end

  alias add <<
end
