require_relative '../lib/rRN4020'

@role = :periphl

@features = { :central => [:central,
                           :enable_authentication,
                           :io_no_input_no_output],
              :periphl => [:enable_authentication,
                           :io_no_input_no_output] }

@server_services = { :central => [:device_information,
                                  :battery],
                     :periphl => [:battery] }

@ports = { :central => '/dev/cu.usbmodem1411',
           :periphl => '/dev/cu.usbmodem1421' }

@bauds = { :central => 115_200,
           :periphl => 19_200 }

@rn = RN4020.new
@rn.open_serial(@ports[@role], @bauds[@role])

def init
  puts
  puts @role
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
  puts "set manufacturer:      #{@rn.manufacturer(:set, 'ACME')}"
  puts "get manufacturer:      #{@rn.manufacturer(:get)}"
  puts "get serial number:     #{@rn.serial_number(:get)}"
  puts "start timer:           " + (@rn.start_timer(:timer_1, 100_000)).to_s
  puts "stop timer:            " + (@rn.stop_timer(:timer_1)).to_s
  puts "set serialized name:   #{@rn.serialized_name(@role.to_s)}"
  puts "get name:              #{@rn.name(:get)}"
  puts "supported features:    #{@rn.supported_features(@features[@role])}"
  puts "server services        #{@rn.server_services(@server_services[@role])}"
  puts @rn.set_connection(10, 2, 10)
  @rn.reboot
  sleep 2
end

def state_to(x)
  @state = x
end

state_to :init

loop do
  case @state
  when :init
    init
    state_to :advertise
  when :advertise
    puts 'advertising'
    @rn.advertise(:start)
    state_to :wait_connect
  when :wait_connect
    count = 0
    loop do
      sleep 1
      count += 1
      puts count
      break if count >= 30
    end
    state_to :advertise_off
  when :advertise_off
    @rn.advertise(:stop)
    state_to :exit
  when :exit
    break
  else
    raise('Error invalid state')
  end
end

@rn.close
