require 'rubyserial'

AOK = "AOK\r\n".freeze
CMD = "CMD\r\n".freeze
CONNECTED = "Connected\r\n"
BONDED = "Bonded\r\n"
SECURED = "Secured\r\n"
CONNECTION_END = "Connection End\r\n".freeze

#@server = nil
#@client = nil

@reading = 1234

def delay(duration = :short)
  sec = case duration
        when :v_short then 0.06
        when :short then 0.1
        when :mid then 0.2
        when :long then  3.0
        else
          raise "Invalid duration in #delay"
        end
  sleep sec
end

def special_puts(x, y)
  return if y.strip.empty?
  print "#{x}: "
  y.split("\n").each_with_index do |line,idx|
    puts line if(idx == 0)
    puts "        " + line unless(idx == 0)
  end
  puts
end

def client_puts(x)
  special_puts('client', x)
end

def server_puts(x)
  special_puts('server', x)
end

def port(mode)
  return @server if mode == :server
  return @client if mode == :client
  raise 'Invalid port in #port'
end

def write(mode, x)
  puts "write #{mode}: #{x}"
  port(mode).write(x + "\r")
end

def write_and_receive(mode, send, rcv)
  write(mode, send)
  buffer = ''
  10.times do |count|
    delay(:v_short)
    read(mode)
    buffer << @buf
#    p buffer
    break if buffer.include?(rcv)
    return false if count == 9
    delay(:mid)
  end
  delay(:v_short)
  true
end

def read(mode)
  @buf = ''
  loop do
    byte = port(mode).getbyte
    @buf << byte if byte
    break unless byte
  end
  special_puts(mode, @buf)
end

def device(mode)
  return '/dev/cu.usbmodem1411' if mode == :client
  return '/dev/cu.usbmodem1421' if mode == :server
  raise 'Invalid mode in #device'
end

def baud(mode)
  return 115_200 if mode == :client
  return 19_200 if mode == :server
  raise 'Invalid mode rate in #baud'
end

def init_port(mode)
  10.times do
    begin
      return Serial.new(device(mode), baud(mode), 8, :none)
    rescue RubySerial::Exception
      delay(:long)
    end
  end
end

@client = init_port(:client)
exit unless @client
@server = init_port(:server)
exit unless @server

delay(:mid)
write(:client, "\n")
write(:server, "\n")
delay(:mid)

loop do
  byte = @client.getbyte
  break unless byte
end

loop do
  byte = @server.getbyte
  break unless byte
end

# client reset
exit unless write_and_receive(:client, 'SF,2', AOK)

# server reset
exit unless write_and_receive(:server, 'SF,2', AOK)

# client reboot
exit unless write_and_receive(:client, 'R,1', CMD)

#server reboot
exit unless write_and_receive(:server, 'R,1', CMD)
#write(:server, 'R,1')
#delay(:long)
#read(:server)

# Set client SS
# GS,00000000
exit unless write_and_receive(:client, 'SS,00000000', AOK)

# Set server SS
# GS,40000000
exit unless write_and_receive(:server, 'SS,00000001', AOK)

# set client features
# GR,80060000  (central, no_keyboard, no_display)
exit unless write_and_receive(:client, 'SR,80060000', AOK)

# set server features
# GR,00060000  (central, no_keyboard, no_display)
exit unless write_and_receive(:server, 'SR,00060000', AOK)

# server clean private services
exit unless write_and_receive(:server, 'PZ', AOK)
# server clean private services
exit unless write_and_receive(:client, 'PZ', AOK)

# server Set private service UUID
exit unless write_and_receive(:server, 'PS,123456789012345678901234567890FF', AOK)

# server Set private service UUID
exit unless write_and_receive(:server, 'PC,12345678901234567890123456789013,02,04', AOK)
# characteristic to be readable, notifiable and 4 byte

# client reboot
exit unless write_and_receive(:client, 'R,1', CMD)

# server reboot
exit unless write_and_receive(:server, 'R,1', CMD)

# client scan
exit unless write_and_receive(:client, 'F', AOK)

# client stop scan
exit unless write_and_receive(:client, 'X', AOK)

# client dump
exit unless write_and_receive(:client, 'D', 'Server Service')

# server dump
exit unless write_and_receive(:server, 'D', 'Server Service')

# client connect
#exit unless write_and_receive(:client, 'E,0,001EC03E38ED', CONNECTED)

# client connect
exit unless write_and_receive(:client, 'E,0,001EC03E38ED', AOK)

# server advertise
exit unless write_and_receive(:server, 'A', CONNECTED)

# client bond
exit unless write_and_receive(:client, 'B', BONDED)

# server bond
exit unless write_and_receive(:server, 'B', SECURED)

# client list services
exit unless write_and_receive(:client, 'LC', 'END')

exit unless write_and_receive(:client, 'LS', 'END')

# server list client services
exit unless write_and_receive(:server, 'LC', 'END')

exit unless write_and_receive(:server, 'LS', 'END')

# server write reading
exit unless write_and_receive(:server, "SUW,12345678901234567890123456789013,#{@reading}", AOK)
@reading += 1

# client dump
exit unless write_and_receive(:client, 'D', 'Server Service')

# server dump
exit unless write_and_receive(:server, 'D', 'Server Service')

# client read reading
#exit unless write_and_receive(:client, 'CURV,12345678901234567890123456789013', AOK)
#CUWC,123456789012345678901234567890FF,1
#  p @buf
#  exit
#end

# client disconnect
exit unless write_and_receive(:client, 'K', CONNECTION_END)

10000.times do
  # server write reading
  exit unless write_and_receive(:server, "SUW,12345678901234567890123456789013,#{@reading}", AOK)
  @reading += 1

  # client reconnect
  write(:client, 'E')
  delay(:v_short)
  read(:client)

  # server advertise
  exit unless write_and_receive(:server, 'A', CONNECTED)

  # server write reading
  #  exit unless write_and_receive(:server, "SUW,12345678901234567890123456789013,#{@reading}", AOK)
#  @reading += 1

  # client read reading
  exit unless write_and_receive(:client, 'CURV,12345678901234567890123456789013', AOK)
#  exit unless write_and_receive(:client, 'CUWC,12345678901234567890123456789013,1', AOK)
#  exit unless write_and_receive(:client, 'CUWC,000B,1', AOK)

  # client disconnect
  exit unless write_and_receive(:client, 'K', CONNECTION_END)

#  delay(:short)
end

# client unbond
exit unless write_and_receive(:client, 'U', AOK)

# server unbond
exit unless write_and_receive(:server, 'U', AOK)

read(:client)
read(:server)
