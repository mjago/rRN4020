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
@debug_count = 0
@reading = 0
@suppress_verbose_output = true
@suppress_write_info = false
@sensor_count = 5
@read_buf = ''
@service = Service.new(PC_UUID, PS_UUID_PREFIX, 5, '02', 4)
@chn = { client: Mode.new('/dev/cu.usbmodem1411',
                          115_200,
                          '00000000',
                          '80060000'),
         server: Mode.new('/dev/cu.usbmodem1421',
                          19_200,
                          '00000001',
                          '00060000') }
@rn_client = RN4020.new('Client', @chn[:client].port, (@chn[:client].baud))
@rn_server = RN4020.new('Server', @chn[:server].port, (@chn[:server].baud))

#   #   #   #   #   #   #   #   #   #   #   #   #   #   #   #

def debug_puts(x)
  if @debug
    puts x
  end
end

def check_comms
  loop do
    break if @rn_client.dump
    sleep 0.1
  end

  loop do
    break if @rn_server.dump
    sleep 0.1
  end
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
  debug_puts 'Error Locked up!'
  debug_puts 'Waiting'
  each_mode { |md| md.write('K') }
  each_mode(&:flush)

  debug_puts 'Retrying...'
  @bad_reads += 1
end

def initial_bond
  debug_puts 'full reset'
  each_mode(&:flush)
  each_mode(&:full_reset)

  debug_puts 'setting services'
  return false  unless @rn_client.server_services(@chn[:client].ss)
  return false  unless @rn_server.server_services(@chn[:server].ss)
  return false  unless @rn_client.options(@chn[:client].sr)
  return false  unless @rn_server.options(@chn[:server].sr)
  return false  unless @rn_client.clean_private_services
  return false  unless @rn_server.clean_private_services
  return false  unless @rn_server.ps(@service.pc_uuid)

  @service.ps_count.times do |count|
    return false  unless @rn_server.pc(@service.ps_uuid_prefix + count.to_s,
                              @service.ps_attribs,
                              @service.ps_size_to_s)
  end

  debug_puts 'reboot'

  each_mode { |md| return false  unless md.reboot }

  debug_puts 'advertise'

  return false  unless @rn_server.advertise

  debug_puts 'scan'

  if @rn_client.scan
    @server_addr = @rn_client.found[0..-3]
    p @server_addr

    debug_puts 'stop scan'

    return false  unless @rn_client.stop_scan

    debug_puts 'connect'

    return false  unless @rn_client.connect(@server_addr)

    debug_puts 'bond'

    return false  unless @rn_client.bond

    debug_puts 'secure'

    return false  unless @rn_server.secure

    debug_puts 'list'

    each_mode do |md|
      return false  unless md.list_client_services
      return false  unless md.list_server_services
    end

    debug_puts 'dump'

    each_mode do |md|
      return false  unless md.dump
    end
    return false  unless @rn_client.disconnect
  end

  @suppress_write_info = true

  each_mode do |md|
    return false  unless md.dump
  end

  debug_puts 'is client bonded?'

  bonded = @rn_client.bonded
  return false unless bonded
  debug_puts 'yes'
  debug_puts "bonded to #{bonded}"
  bonded
end

def exchange_values
  loop do
    puts "\ncount: #{@count}"
    debug_puts "bad_reads: #{@bad_reads}" if @bad_reads > 0
    debug_puts 'writing readings?'

    @rn_server.wake
    each_sensor do |sn|
      break unless @rn_server.write_reading(PS_UUID_PREFIX + sn,
                                            formatted_reading)
    end

    debug_puts 'reconnecting'

    @rn_client.reconnect

    sleep 0.05

    @debug_count += 1
    if(@debug_count % 64 == 34) ###   #   #   #   #   #   #   #   #   #   #
      puts 'breaking'
      return false
    end

    debug_puts 'advertising to connect'

    break unless @rn_server.advertise_to_connect

    debug_puts 'waiting for connection'
    break unless @rn_client.wait_for_connection

    if(@count % 4 == 0)
      break unless @rn_client.dump
      puts "client bta       = #{@rn_client.bta       }"
      puts "client name      = #{@rn_client.name      }"
      puts "client role      = #{@rn_client.role      }"
      puts "client connected = #{@rn_client.connected }"
      puts "client bonded    = #{@rn_client.bonded    }"
      puts "client ss        = #{@rn_client.ss        }"
    end

    if(@count % 4 == 2)
      break unless @rn_server.dump
      puts "server bta       = #{@rn_server.bta       }"
      puts "server name      = #{@rn_server.name      }"
      puts "server role      = #{@rn_server.role      }"
      puts "server connected = #{@rn_server.connected }"
      puts "server bonded    = #{@rn_server.bonded    }"
      puts "server ss        = #{@rn_server.ss        }"
    end

    debug_puts 'reading values'

    if (@debug_count % 64 == 6) ###   #   #   #   #   #   #   #   #   #   #
      puts 'breaking'
      return false
    end

    # client read reading
    each_sensor do |sn|
      value = @rn_client.read_value(PS_UUID_PREFIX + sn)
      puts "client read #{value}"
      break unless value == formatted_reading
    end

    debug_puts 'disconnecting'

    break unless @rn_client.disconnect
    break unless @rn_server.wait_for_disconnect
    @count += 1
    @reading += 1
    @reading = 0 if @reading > 65_535

#    debug_puts 'go dormant'
#    @rn_server.go_dormant
    return true
  end
  false
end

def run_test
  @peripheral = ''
  loop do
    @peripheral = initial_bond
    break unless @peripheral.empty?
    debug_puts 'retrying'
    unbond
  end
  loop do
    next if exchange_values
    @rn_client.disconnect
    @rn_server.wait_for_disconnect
    @rn_server.go_dormant
    sleep 2
  end
end

def unbond
  debug_puts 'unbond'
  each_mode do |md|
    next unless md.unbond
    md.read
  end
end

### Start

check_comms
run_test

