require_relative '../lib/rRN4020'

features = [:central,
            :real_time_read,
            :auto_advertise,
            :support_mldp,
            :enable_authentication,
            :io_no_input_no_output,
            :mldp_without_status]

server_services = [:device_information,
                   :user_defined_private_service]

serial_port = '/dev/cu.usbmodem1421'

rn = RN4020.new
rn.open_serial(serial_port)
puts rn.v
puts rn.serialized_name 'server'
puts rn.baud(115200)
puts rn.model('iBand_srv_1')
puts rn.manufacturer('Microchip')
puts rn.factory_default(:partial)
#puts rn.supported_features(features)
puts rn.sr(features)
#puts rn.server_services(server_services)
puts rn.ss(server_services)
#puts rn.set_connection(0x100, 2, 0x100)
puts rn.st(0x100, 2, 0x100)
rn.scan(:start)
sleep 4
rn.scan(:stop)

rn.close

