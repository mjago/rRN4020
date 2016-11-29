require_relative '../lib/rRN4020'

@role = :central

@features = { :central => [:central],
             :periphl => [:enable_authentication,
                          :io_no_input_no_output] }

@server_services = { :central => [:device_information,
                                 :battery,
                                 :user_defined_private_service],
                    :periphl => [:device_information,
                                 :battery] }

@ports = { :central => '/dev/cu.usbmodem1411',
          :periphl => '/dev/cu.usbmodem1421' }

@bauds = { :central => 115_200,
          :periphl => 19_200 }

@rn = RN4020.new
@rn.open_serial(@ports[@role], @bauds[@role])

sleep 2

def state_to x
  @state = x
end

def init
  puts
  puts @role
  #    1.upto(10) do |count|
  #      print count.to_s + ', '
  #      sleep 0.25
  #    end
  # puts @rn.v
  # puts @rn.serialized_name 'server'
  # puts @rn.baud(115200)
  # puts @rn.model('central_1')
  # puts @rn.manufacturer('Acme')
  # puts @rn.factory_default(:partial)
  # puts @rn.supported_features(features)
  # puts @rn.server_services(server_services)
  # puts @rn.set_connection(0x100, 2, 0x100)
  #@rn.scan(:start)
  #sleep 4
  #@rn.scan(:stop)
  @rn.write("\n")
  @rn.read
  puts @rn.factory_default(:partial)
  sleep 0.1
  puts @rn.factory_default(:partial)
  puts "set software revision: #{@rn.software_revision(:set, '1.21')}"
  puts "get software revision: #{@rn.software_revision(:get)}"
  puts "set software revision: #{@rn.software_revision(:set, '1.10')}"
  puts "get software revision: #{@rn.software_revision(:get)}"
  puts "set model:             #{@rn.model(:set, 'RN4020')}"
  puts "get model:             #{@rn.model(:get)}"
  puts "set manufacturer:      #{@rn.manufacturer(:set, 'iBandage')}"
  puts "get manufacturer:      #{@rn.manufacturer(:get)}"
  puts "get serial number:     #{@rn.serial_number(:get)}"
  puts "start timer:           " + (@rn.start_timer(:timer_1, 100_000)).to_s
  puts "stop timer:            " + (@rn.stop_timer(:timer_1)).to_s
  puts "set serialized name:   #{@rn.serialized_name(@role.to_s)}"
  puts "get name:              #{@rn.name(:get)}"
  puts @rn.supported_features(@features[@role])
  puts @rn.server_services(@server_services[@role])
  puts @rn.set_connection(10, 2, 10)
  @rn.reboot
  sleep 2
end

def check_scan
  scan = @rn.read
  puts "scan = #{scan}"
  if scan.length > 0
    scan_ary = scan.split(',')
    puts "scan_ary #{scan_ary}"
    puts "scan_ary length is #{scan_ary.length}"
    if scan_ary.length == 4
      if scan_ary[2].include?('periphl_')
        @rn.scan(:stop)
        @periphl_id = scan_ary[0]
        puts "@periphl_id = #{@periphl_id}"
        return true
      end
    end
  end
end

state_to :init

loop do
  case @state
  when :init
    init
    state_to :check_dump
  when :check_dump
    dump = "dump: #{@rn.write_and_return('D')}"
    dump_ary = dump.split("\n")
    p dump_ary
    if dump_ary[3].include?('Connected=001EC03E38ED')
      state_to :reconnect
    else
      state_to :scan
    end
  when :scan
    puts 'scanning'
    p @rn.scan(:start)
    p "data = #{@rn.data}"
    state_to :wait_connect
  when :wait_connect
    count = 0
    loop do
      if check_scan
        state_to :connect
        break
      end
      sleep 1
      count += 1
      puts count
      state_to :scan_off if count >= 30
      break if count >= 30
    end
  when :connect
    puts 'connecting'
    @rn.connect(@periphl_id)
    state_to :bond
  when :reconnect
    puts 'reconnecting'
    puts "reconnect: #{@rn.reconnect}"
    state_to :bond
  when :bond
    puts 'bonding'
    @rn.bond()
    state_to :read_battery
  when :scan_off
    @rn.scan(:stop)
    state_to :disconnect
  when :read_battery
    puts "battery = #{@rn.read_battery}"
    state_to :disconnect
  when :disconnect
    puts 'disconnecting'
#    puts "disconnecting #{@rn.disconnect}"
    state_to :exit
  when :exit
    puts 'exiting'
    break
  else
    raise("Error invalid state")
  end
end

@rn.close
