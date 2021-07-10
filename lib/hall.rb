# frozen_string_literal: true

require 'securerandom'
require_relative 'exeption'
require_relative 'logging'
require_relative 'frame'

# Talkroom
class Hall
  include SocketPanda::Logging
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
    name = guest.roommate&.name
    name ||= 'alone'
    logger.info "#{guest.name || 'Guest'} joined room ##{number} #{name}"
  end

  def new_room_number
    number = SecureRandom.random_number(999_999).to_s.rjust(6, '0').to_sym
    return number unless rooms[number]

    new_room_number
  end
end

# Serve as components for the hall
# Can only be occupied by two
class Room
  include SocketPanda::Logging
  attr_accessor :guests, :id

  def initialize(id, host = nil)
    @id = id
    @guests = []
    self << host if host
  end

  def <<(guest)
    raise RoomFullError, "Talkroom ##{id} is full" if guests.length > 1

    guests << guest
    notify_new_guest
  end

  def other(guest)
    return unless full? && (index = guests.index(guest))

    guests[index - 1]
  end

  def notify_new_guest
    call "ROOM #{id}", guests[-1]
    broker
  end

  # Make a phone call to the guests from the reception
  def call(text, guest)
    return logger.warn 'No guest available to call' unless guest

    PandaFrame::OutgoingText.new(text).deliver guest
  end

  # Notify both party of their names
  def broker
    return unless guests[1]

    call "PEER #{guests[1].name}", guests[0]
    call "PEER #{guests[0].name}", guests[1]
  end

  def checkout(guest)
    return unless guests.delete guest

    logger.warn "Guest #{guest.name} left room ##{id}"
    call "POUT #{guest.name}", guests[-1]
  end

  alias add <<

  private

  def full?
    !!guests[1]
  end
end
