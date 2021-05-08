require 'securerandom'

# Talkroom
class Hall < Hash
  # room should be symbol
  def checkin(guest, room = nil)
    self[guest.room]&.delete(guest)
    room = room&.to_sym
    room ||= new_room
    self[room] ||= []
    self[room] << guest
    guest.room = room
    warn "[INFO] Guest joined room ##{room} with #{self[room]}"
    true
  end

  def new_room
    number = SecureRandom.alphanumeric.to_sym
    return number unless self[number]

    new_room
  end
end
