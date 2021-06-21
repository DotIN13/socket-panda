require 'evt'

@scheduler = Evt::Scheduler.new
Fiber.set_scheduler @scheduler

@server = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
@server.bind Addrinfo.tcp '127.0.0.1', 3002
@server.listen Socket::SOMAXCONN

def handle_socket(socket)
  line = ''
  until line == "CLOSE\r\n" || line.nil?
    socket.wait(0b001, 5)
    line = socket.gets
    p line
  end
  socket.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
  socket.close
end

Fiber.schedule do
  loop do
    socket, _addr = @server.accept
    Fiber.schedule do
      warn 'New socket'
      handle_socket(socket)
    end
  end
end

@scheduler.run
