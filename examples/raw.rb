require 'rubyserial'
require_relative 'rn4020'

SERVER_MAC_ADDR =  '001EC03E38ED'.freeze
PC_UUID = '123456789012345678901234567890FF'.freeze
PS_UUID_PREFIX = '1234567890123456789012345678904'.freeze # final digit missing!

Mode = Struct.new(:device, :baud, :ss, :sr, :port)

Service = Struct.new(:pc_uuid, :ps_uuid_prefix, :ps_count, :ps_attribs, :ps_size) do
  def ps_size_to_s
    '0' << ps_size.to_s
  end
end

@rn = RN4020.new
@bad_reads = 0
@count = 0
@reading = 0
@suppress_verbose_output = true
@suppress_write_info = false
@sensor_count = 5
@read_buf = ''
client_mode = Mode.new('/dev/cu.usbmodem1411',
                       115_200,
                       '00000000',
                       '80060000',
                       nil)

server_mode = Mode.new('/dev/cu.usbmodem1421',
                       19_200,
                       '00000001',
                       '00060000',
                       nil)

@chn = { client: client_mode, server: server_mode }
@service = Service.new(PC_UUID, PS_UUID_PREFIX, 5, '02', 4)

#   #   #   #   #   #   #   #   #   #   #   #   #   #   #   #

def init_ports
  each_mode do |md|
    init_port(md)
    @rn.write(@chn[md].port, "\n" * 2)
  end
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

def init_port(mode)
  10.times do
    begin
      @chn[mode].port = Serial.new(@chn[mode].device,
                                     @chn[mode].baud, 8, :none)
    rescue RubySerial::Exception
      sleep 1
    end
  end
end

def each_mode
  @chn.each_key { |md| yield(md) }
end

def each_sensor
  @service.ps_count.times do |count|
    yield(count.to_s)
  end
end

def formatted_reading
  sprintf("%#{@service.ps_size_to_s}X", @reading)
end

def retry
  puts 'Error Locked up!'
  puts 'Waiting'
  each_mode { |md| @rn.write(@chn[md].port, 'K') }
  sleep 2
  each_mode { |md| @rn.flush(@chn[md].port) }

  puts 'Retrying...'
  @bad_reads += 1
end

def run_test
  each_mode { |md| @rn.flush(@chn[md].port) }
  each_mode { |md| @rn.full_reset(@chn[md].port) }

  each_mode do |md|
    exit unless @rn.server_services(@chn[md].port, @chn[md].ss)
    exit unless @rn.options(@chn[md].port, @chn[md].sr)
    exit unless @rn.clean_private_services(@chn[md].port)
  end

  exit unless @rn.ps(@chn[:server].port, @service.pc_uuid)

  @service.ps_count.times do |count|
    exit unless @rn.pc(@chn[:server].port,
                       @service.ps_uuid_prefix + count.to_s,
                       @service.ps_attribs,
                       @service.ps_size_to_s)
  end

  each_mode do |md|
    exit unless @rn.reboot(@chn[md].port)
  end

  exit unless @rn.scan(@chn[:client].port)

  exit unless @rn.stop_scan(@chn[:client].port)

  each_mode do |md|
    exit unless @rn.dump(@chn[md].port)
  end

  exit unless @rn.connect(@chn[:client].port, SERVER_MAC_ADDR)

  exit unless @rn.advertise(@chn[:server].port)

  exit unless @rn.bond(@chn[:client].port)

  exit unless @rn.secure(@chn[:server].port)

  each_mode do |md|
    exit unless @rn.list_client_services(@chn[md].port)
    exit unless @rn.list_server_services(@chn[md].port)
  end

  each_mode do |md|
    exit unless @rn.dump(@chn[md].port)
  end

  exit unless @rn.disconnect(@chn[:client].port)

  @suppress_write_info = true

  loop do
    loop do
      puts "\ncount: #{@count}"
      puts "bad_reads: #{@bad_reads}" if @bad_reads > 0

      each_sensor do |count|
        break unless @rn.write_reading(@chn[:server].port,
                                       PS_UUID_PREFIX + count,
                                       formatted_reading)
      end

      @rn.reconnect(@chn[:client].port)

      break unless @rn.advertise(@chn[:server].port)

      break unless @rn.wait_for_connection(@chn[:client].port)

      # client read reading
      each_sensor do |count|
        value = @rn.read_value(@chn[:client].port, PS_UUID_PREFIX + count)
        puts value
        break unless value == formatted_reading
      end

      break unless @rn.disconnect(@chn[:client].port)
      @count += 1
      @reading += 1
      @reading = 0 if @reading > 65535
    end

    reset
  end
end

def exit
  each_mode do |md|
    next unless @rn.unbond(@chn[md].port)
    @rn.read(md)
  end
end

### Start

init_ports
run_test
exit
