require 'rubyserial'

AOK = "AOK\r\n".freeze
CMD = "CMD\r\n".freeze
CONNECTED = "Connected\r\n"
BONDED = "Bonded\r\n"
SECURED = "Secured\r\n"
CONNECTION_END = "Connection End\r\n".freeze
SERVER_SERVICE = 'Server Service'.freeze
FULL_RESET = 'SF,2'.freeze
CLEAN_PRIVATE_SERVICES = 'PZ'.freeze
REBOOT = 'R,1'.freeze
SCAN = 'F'.freeze
STOP_SCAN = 'X'.freeze
DUMP = 'D'.freeze
ADVERTISE = 'A'.freeze
BOND = 'B'.freeze
LIST_CLIENT_SERVICES = 'LC'.freeze
LIST_SERVER_SERVICES = 'LS'.freeze
CLASS_UUID =   '123456789012345678901234567890FF'.freeze
SERVICE_UUID = '1234567890123456789012345678904'.freeze
#SERVICE_UUID_2 = '12345678901234567890123456789026'.freeze
#SERVICE_UUID_3 = '12345678901234567890123456789027'.freeze
#SERVICE_UUID_4 = '12345678901234567890123456789028'.freeze
@bad_reads = 0
@iters = 60
@count = 0
@reading = 0
@modes = [:client, :server]
@suppress_verbose_output = true
@suppress_write_info = false
@sensor_count = 5
@read_buf = {}
@ports = {}
@ss = { :client => '00000000',
        :server => '00000001' }

@sr = { :client => '80060000',
        :server => '00060000' }

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
  return if @suppress_verbose_output
  return if y.strip.empty?
  print "#{x}: "
  y.split("\n").each_with_index do |line,idx|
    puts line if(idx == 0)
    puts "        " + line unless(idx == 0)
  end
  puts
end

def port(mode)
  @ports[mode]
  #  return @server if mode == :server
  #  return @client if mode == :client
  #  raise 'Invalid port in #port'
end

def write(mode, x)
  print 'write' unless @suppress_verbose_output
  puts " #{mode}: #{x}" unless x.empty? unless @suppress_write_info
  port(mode).write(x + "\r")
end

def write_and_receive(mode, send, rcv)
  write(mode, send)
  @read_buf[mode] = ''
  @iters.times do |count|
    delay(:v_short)
    @read_buf[mode] << read(mode)
    #    p @read_buf[mode]
    break if @read_buf[mode].include?(rcv)
    return false if count == 9
    delay(:v_short) unless send == REBOOT
    delay(:short) if send == REBOOT
  end
  true
end

def read(mode)
  buffer = ''
  loop do
    byte = port(mode).getbyte
    buffer << byte if byte
    break unless byte
  end
  special_puts(mode, buffer)
  buffer
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
      delay(:short)
    end
  end
end

def flush(mode)
  loop do
    byte = @ports[mode].getbyte
    break unless byte
  end
end

def read_value(mode, uuid)
  @read_buf[mode] = ''
  return nil unless write(mode, "CURV,#{uuid}")
  @iters.times do |count|
    delay(:v_short)
    @read_buf[mode] << read(mode)
    break if @read_buf[mode].include?(AOK)
    return nil if count == 9
    delay(:v_short)
  end
  (/R,([0-9,a-f,A-F]*)\./).match(@read_buf[mode])
  value = Regexp.last_match(1)
  puts "#{mode}: value_#{uuid[-1..-1]}(#{value})" if value
  return value
end

def each_mode
  @modes.each do |mode|
    yield(mode)
  end
end

def each_sensor
  @sensor_count.times do |count|
    yield(count.to_s)
  end
end

def full_reset(mode)
  loop { break if write_and_receive(mode, FULL_RESET, AOK) }
  exit unless write_and_receive(mode, 'R,1', CMD)
end

def init_read_buf
  each_mode { |md| @read_buf[md] = '' }
end

def init_ports
  each_mode do |mode|
    @ports[mode] = init_port(mode)
    write(mode, "\n" * 2)
    delay(:v_short)
  end
end
#   #   #   #   #   #   #   #   #   #   #   #   #   #   #   #   #   #   #   #

#@ports[:server] = init_port(:server)
#@ports[:client] = init_port(:client)

init_read_buf
init_ports

each_mode{ |m| flush(m) }
each_mode{ |m| full_reset(m) }

#each_mode do |mode|
#  loop do
#    break if write_and_receive(mode, FULL_RESET, AOK)
#  end
#  exit unless write_and_receive(mode, 'R,1', CMD)
#end

each_mode do |mode|
  exit unless write_and_receive(mode, "SS,#{@ss[mode]}", AOK)
  exit unless write_and_receive(mode, "SR,#{@sr[mode]}", AOK)
  exit unless write_and_receive(mode, CLEAN_PRIVATE_SERVICES, AOK)
end

exit unless write_and_receive(:server, "PS,#{CLASS_UUID}", AOK)

each_sensor do |count|
  exit unless write_and_receive(:server, "PC,#{SERVICE_UUID + count},02,04", AOK)
end
#  exit unless write_and_receive(:server, "PC,#{SERVICE_UUID_2},02,04", AOK)
#  exit unless write_and_receive(:server, "PC,#{SERVICE_UUID_3},02,04", AOK)
#  exit unless write_and_receive(:server, "PC,#{SERVICE_UUID_4},02,04", AOK)

each_mode do |mode|
  exit unless write_and_receive(mode, REBOOT, CMD)
end

# client scan
exit unless write_and_receive(:client, SCAN, AOK)

# client stop scan
exit unless write_and_receive(:client, STOP_SCAN, AOK)

each_mode do |mode|
  exit unless write_and_receive(mode, DUMP, SERVER_SERVICE)
end

# client connect
exit unless write_and_receive(:client, 'E,0,001EC03E38ED', AOK)

# server advertise
exit unless write_and_receive(:server, ADVERTISE, CONNECTED)

# client bond
exit unless write_and_receive(:client, BOND, BONDED)

# server bond
exit unless write_and_receive(:server, BOND, SECURED)

each_mode do |mode|
  exit unless write_and_receive(mode, LIST_CLIENT_SERVICES, 'END')
  exit unless write_and_receive(mode, LIST_SERVER_SERVICES, 'END')
end

# server write reading
#exit unless write_and_receive(:server, "SUW,#{SERVICE_UUID},#{@reading}", AOK)
#exit unless write_and_receive(:server, "SUW,#{SERVICE_UUID},#{@reading}", AOK)

each_mode do |mode|
  exit unless write_and_receive(mode, DUMP, SERVER_SERVICE)
end

# client disconnect
exit unless write_and_receive(:client, 'K', CONNECTION_END)

@suppress_write_info = true

loop do
  loop do
    puts "\ncount: #{@count}"
    puts "bad_reads: #{@bad_reads}" if @bad_reads > 0
    puts "iters: #{@iters}" if @iters > 35

    each_sensor do |count|
      break unless write_and_receive(:server, "SUW,#{SERVICE_UUID + count},#{sprintf('%04d', @reading)}", AOK)
    end

    # client reconnect
    write(:client, 'E')

    #todo    delay(:v_short)
    #    read(:client)

    # server advertise
    break unless write_and_receive(:server, 'A', CONNECTED)
    retries = 0
    @read_buf[:client] = ''
    @iters.times do
      @read_buf[:client] << read(:client)
      break if @read_buf[:client].include?(CONNECTED)
      delay(:v_short)
      retries += 1
    end
    break if retries == @iters

    # client read reading
    each_sensor do |count|
      break unless read_value(:client, SERVICE_UUID + count) == sprintf('%04d', @reading)
    end
    # #     break unless read_value(:client, SERVICE_UUID_2)
    #    break unless read_value(:client, SERVICE_UUID_3)
    #    break unless read_value(:client, SERVICE_UUID_4)

    #    delay(:v_short)
    # client disconnect
    break unless write_and_receive(:client, 'K', CONNECTION_END)

    #  delay(:short)
    @count += 1
    @reading += 1
    @reading = 0 if @reading >= 10000
  end
  puts 'Error Locked up!'
  puts 'Waiting'
  each_mode { |md| write(md, 'K') }
  sleep 2
  each_mode { |md| flush(md) }
  puts 'Retrying...'
  @bad_reads += 1
  @iters += 1
end

each_mode do |mode|
  exit unless write_and_receive(mode, 'U', AOK)
  read(mode)
end
