require 'rubyserial'
require_relative 'rn4020'

SERVER_MAC_ADDR = '001EC03E38ED'.freeze
PC_UUID =        '123456789012345678901234567890FF'.freeze
PS_UUID_PREFIX = '1234567890123456789012345678904'.freeze # final digit added later!

Mode = Struct.new(:port, :baud, :ss, :sr)

Service = Struct.new(:pc_uuid, :ps_uuid_prefix, :ps_count, :ps_attribs, :ps_size) do
  def ps_size_to_s
    '0' << ps_size.to_s
  end
end

@bad_reads = 0
@count = 0
@reading = 0
@suppress_verbose_output = true
@suppress_write_info = false
@sensor_count = 5
@read_buf = ''

@chn = { client: Mode.new('/dev/cu.usbmodem1411',
                          115_200,
                          '00000000',
                          '80060000'),
         server: Mode.new('/dev/cu.usbmodem1421',
                          19_200,
                          '00000001',
                          '00060000') }

@rn_client = RN4020.new(@chn[:client].port, (@chn[:client].baud))
@rn_server = RN4020.new(@chn[:server].port, (@chn[:server].baud))
@service = Service.new(PC_UUID, PS_UUID_PREFIX, 5, '02', 4)

#   #   #   #   #   #   #   #   #   #   #   #   #   #   #   #

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

def each_mode
  [@rn_client, @rn_server].each { |md| yield(md) }
end

def each_sensor
  @service.ps_count.times do |count|
    yield(count.to_s)
  end
end

def formatted_reading
  sprintf("%#{@service.ps_size_to_s}X", @reading)
end

def reset
  puts 'Error Locked up!'
  puts 'Waiting'
  each_mode { |md| md.write('K') }
  sleep 2
  each_mode { |md| md.flush }

  puts 'Retrying...'
  @bad_reads += 1
end

def run_test
  each_mode { |md| md.flush }
  each_mode { |md| md.full_reset }

  exit unless @rn_client.server_services(@chn[:client].ss)
  exit unless @rn_server.server_services(@chn[:server].ss)
  exit unless @rn_client.options(@chn[:client].sr)
  exit unless @rn_server.options(@chn[:server].sr)
  exit unless @rn_client.clean_private_services
  exit unless @rn_server.clean_private_services
  exit unless @rn_server.ps(@service.pc_uuid)

  @service.ps_count.times do |count|
    exit unless @rn_server.pc(@service.ps_uuid_prefix + count.to_s,
                              @service.ps_attribs,
                              @service.ps_size_to_s)
  end

  each_mode { |md| exit unless md.reboot }

  exit unless @rn_server.advertise

  if @rn_client.scan
    @server_addr = @rn_client.found[0..-3]
    p @server_addr
    exit unless @rn_client.stop_scan
    exit unless @rn_client.connect(@server_addr)
    exit unless @rn_client.bond

    exit unless @rn_server.secure

    each_mode do |md|
      exit unless md.list_client_services
      exit unless md.list_server_services
    end

    each_mode do |md|
      exit unless md.dump
    end
    exit unless @rn_client.disconnect
  end

  @suppress_write_info = true

  if @rn_client.bonded
    puts "bonded = #{@rn_client.bonded}"
    loop do
      loop do
        puts "\ncount: #{@count}"
        puts "bad_reads: #{@bad_reads}" if @bad_reads > 0

        each_sensor do |sn|
          break unless @rn_server.write_reading(PS_UUID_PREFIX + sn,
                                                formatted_reading)
        end

        @rn_client.reconnect
        break unless @rn_server.advertise
        break unless @rn_client.wait_for_connection

        break unless @rn_client.dump if(@count % 32 == 8)
        puts "bta       = #{@rn_client.bta       }" if(@count % 32 == 8)
        puts "name      = #{@rn_client.name      }" if(@count % 32 == 8)
        puts "role      = #{@rn_client.role      }" if(@count % 32 == 8)
        puts "connected = #{@rn_client.connected }" if(@count % 32 == 8)
        puts "bonded    = #{@rn_client.bonded    }" if(@count % 32 == 8)
        puts "ss        = #{@rn_client.ss        }" if(@count % 32 == 8)

        break unless @rn_server.dump if(@count % 32 == 24)
        puts "bta       = #{@rn_server.bta       }" if(@count % 32 == 24)
        puts "name      = #{@rn_server.name      }" if(@count % 32 == 24)
        puts "role      = #{@rn_server.role      }" if(@count % 32 == 24)
        puts "connected = #{@rn_server.connected }" if(@count % 32 == 24)
        puts "bonded    = #{@rn_server.bonded    }" if(@count % 32 == 24)
        puts "ss        = #{@rn_server.ss        }" if(@count % 32 == 24)

        # client read reading
        each_sensor do |sn|
          value = @rn_client.read_value(PS_UUID_PREFIX + sn)
          puts value
          break unless value == formatted_reading
        end

        break unless @rn_client.disconnect
        @count += 1
        @reading += 1
        @reading = 0 if @reading > 65535
      end

      reset
    end
  end
end

def exit
  each_mode do |md|
    next unless md.unbond
    md.read
  end
end

### Start

run_test
exit
