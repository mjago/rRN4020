class RN4020

  AOK = "AOK\r\n".freeze
  CMD = "CMD\r\n".freeze
  REBOOT = 'R,1'.freeze
  FULL_RESET = 'SF,2'.freeze
  SS = 'SS'.freeze
  SR = 'SR'.freeze
  CLEAN_PRIVATE_SERVICES = 'PZ'.freeze
  LIST_CLIENT_SERVICES = 'LC'.freeze
  LIST_SERVER_SERVICES = 'LS'.freeze
  SCAN = 'F'.freeze
  STOP_SCAN = 'X'.freeze
  DUMP = 'D'.freeze
  SERVER_SERVICE = 'Server Service'.freeze
  ADVERTISE = 'A'.freeze
  CONNECTED = "Connected\r\n".freeze
  BOND = 'B'.freeze
  BONDED = "Bonded\r\n".freeze
  SECURED = "Secured\r\n".freeze
  CONNECTION_END = "Connection End\r\n".freeze

  def write(port, x)
    #  print 'write' unless @suppress_verbose_output
    #  puts " #{mode}: #{x}" unless x.empty? unless @suppress_write_info
    port.write(x + "\r")
  end

  def write_and_receive(port, send, rcv)
    write(port, send)
    @read_buf = ''
    60.times do |count|
      delay(:v_short)
      @read_buf << read(port)
      break if @read_buf.include?(rcv)
      return false if count == 9
      delay(:v_short) unless send == REBOOT
      delay(:short) if send == REBOOT
    end
    true
  end

  def read(port)
    buffer = ''
    loop do
      byte = port.getbyte
      buffer << byte if byte
      break unless byte
    end
    #  special_puts(mode, buffer)
    buffer
  end

  def delay(duration = :short)
    sec = case duration
          when :v_short then 0.06
          when :short then 0.1
          else
            raise "Invalid duration in #delay"
          end
    sleep sec
  end

  def read_and_receive(port, rcv)
    @read_buf = ''
    60.times do |retries|
      @read_buf << read(port)
      break if @read_buf.include?(rcv)
      delay(:v_short)
      return false if retries == 59
    end
    true
  end

  def read_value(port, uuid)
    @read_buf = ''
    return nil unless write(port, "CURV,#{uuid}")
    60.times do |count|
      delay(:v_short)
      @read_buf << read(port)
      break if @read_buf.include?(AOK)
      return nil if count == 9
    end
    /R,([0-9,a-f,A-F]*)\./.match(@read_buf)
    value = Regexp.last_match(1)
    #  puts "#{mode}: value_#{uuid[-1..-1]}(#{value})" if value
    value
  end

  def flush(port)
    loop do
      byte = port.getbyte
      break unless byte
    end
  end

  def full_reset(port)
    write_and_receive(port, FULL_RESET, AOK)
  end

  def reboot(port)
    write_and_receive(port, REBOOT, CMD)
  end

  def server_services(port, ss)
    write_and_receive(port, "SS,#{ss}", AOK)
  end

  def options(port, sr)
    write_and_receive(port, "SR,#{sr}", AOK)
  end

  def clean_private_services(port)
    write_and_receive(port, CLEAN_PRIVATE_SERVICES, AOK)
  end

  def ps(port, uuid)
    write_and_receive(port, "PS,#{uuid}", AOK)
  end

  def pc(port, uuid, attribs, size)
    write_and_receive(port, "PC,#{uuid},#{attribs},#{size}", AOK)
  end

  def scan(port)
    write_and_receive(port, SCAN, AOK)
  end

  def stop_scan(port)
    write_and_receive(port, STOP_SCAN, AOK)
  end

  def dump(port)
    write_and_receive(port, DUMP, SERVER_SERVICE)
  end

  def connect(port, mac)
    write_and_receive(port, "E,0,#{mac}", AOK)
  end

  def advertise(port)
    write_and_receive(port, ADVERTISE, CONNECTED)
  end

  def bond(port)
    write_and_receive(port, BOND, BONDED)
  end

  def secure(port)
    write_and_receive(port, BOND, SECURED)
  end

  def list_client_services(port)
    write_and_receive(port, LIST_CLIENT_SERVICES, 'END')
  end

  def list_server_services(port)
    write_and_receive(port, LIST_SERVER_SERVICES, 'END')
  end

  def disconnect(port)
    write_and_receive(port, 'K', CONNECTION_END)
  end

  def write_reading(port, uuid, value)
    write_and_receive(port, "SUW,#{uuid},#{value}", AOK)
  end

  def reconnect(port)
    write(port, 'E')
  end

  def wait_for_connection(port)
    read_and_receive(port, CONNECTED)
  end

  def unbond(port)
    write_and_receive(port, 'U', AOK)
  end
end
