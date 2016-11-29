# encoding ascii-8bit

require 'rubyserial'

class RN4020

  attr_reader :data

  def open_serial(port, baud = 115_200)
    @serialport = Serial.new(port, baud, 8, :none)
  end

  def close_serial
    @serialport.close if @serialport
  end

  def close
    close_serial
  end

  def write(cmd)
    @serialport.write(cmd + "\n")
  end

  def read(timeout = 0.2)
    buf = ''
    cutoff = Time.now + timeout
    loop do
      byte = @serialport.getbyte
      buf << byte if byte
      break if Time.now > cutoff
#      break if byte == "\r"
    end
    buf
  end

  def paired?
    !@paired.nil?
  end

  def write_and_verify(str_out, partial)
    retries = 10
    data = ''
    write(str_out)
    retries.times do |count|
      sleep 0.05
      x = read
      data << x
      break if x.include? partial
      return false if x.include?('ERR') || (count == (retries - 1))
    end
    true
  end

  def version
    write_and_return('V')
  end

  def factory_default(mode = :partial)
    return write_and_verify("SF,1", 'AOK') if mode == :partial
    return write_and_verify("SF,2", 'AOK') if mode == :full
    raise "Invalid Mode"
  end

  def baud(rate)
    return false unless write_and_verify("SF,#{rate}", 'AOK')
    rate.to_s
  end

  def write_and_return(cmd)
    write(cmd)
    read()
  end

  def serialized_name(name)
    write_and_verify("S-,#{name}", 'AOK')
  end

  def model(mode, cmd = nil)
    return write_and_return("GDM") if mode == :get
    return write_and_verify("SDM,#{cmd}", 'AOK') if mode == :set
    raise "Invalid Mode"
  end

  def manufacturer(mode, cmd = nil)
    return write_and_return("GDN") if mode == :get
    return write_and_verify("SDN,#{cmd}", 'AOK') if mode == :set
    raise "Invalid Mode"
  end

  def software_revision(mode, cmd = nil)
    return write_and_return("GDR") if mode == :get
    return write_and_verify("SDR,#{cmd}", 'AOK') if mode == :set
    raise "Invalid Mode"
  end

  def serial_number(mode, cmd = nil)
    return write_and_return("GDS") if mode == :get
    return write_and_verify("SDS,#{cmd}", 'AOK') if mode == :set
    raise "Invalid Mode"
  end

  def valid_timer?(timer)
    timer.to_s =~ /^timer_[123]$/
  end

  def valid_timer_value?(val)
    (val > 0 && val < 0x80000000)
  end

  def start_timer(timer, value)
    if valid_timer?(timer)
      if valid_timer_value?(value)
        write_and_verify("SM,#{(timer.to_s)[6..6]},#{sprintf("%08x", value)}",'AOK')
      else
        raise 'Invalid value'
      end
    else
      raise 'Invalid timer'
    end
  end

  def stop_timer(timer)
    if valid_timer?(timer)
      write_and_verify("SM,#{timer.to_s[6..6]},FFFFFFFF", 'AOK')
    end
  end

  def name(mode, text = nil)
    return write_and_verify("SN,#{text}", 'AOK') if mode == :set
    return write_and_return('GN') if mode == :get
    raise "Invalid Mode"
  end

  def supported_features(settings)
    bits = 0
    settings.each do |setting|
      case setting
      when :central
        bits |= (1 << 31)
      when :real_time_read
        bits |= (1 << 30)
      when :auto_advertise
        bits |= (1 << 29)
      when :support_mldp
        bits |= (1 << 28)
      when :auto_mldp_disable
        bits |= (1 << 27)
      when :no_direct_advertisement
        bits |= (1 << 26)
      when :uart_flow_control
        bits |= (1 << 25)
      when :run_script_after_power_on
        bits |= (1 << 24)
      when :enable_authentication
        bits |= (1 << 22)
      when :enable_rempte_command
        bits |= (1 << 21)
      when :do_not_save_bonding
        bits |= (1 << 20)
      when :io_keyboard_display
        bits |= (1 << 19)
      when :io_keyboard_only
        bits |= (1 << 18)
      when :io_no_input_no_output
        bits |= (11 << 18)
      when :io_display_yes_no
        bits |= (1 << 17)
      # when :io_display_only
      # ?
      when :blk_set_cmds_in_remote_cmd_mode
        bits |= (1 << 16)
      when :enable_ota
        bits |= (1 << 15)
      when :ios_mode
        bits |= (1 << 14)
      when :server_only
        bits |= (1 << 13)
      when :enable_uart_in_script
        bits |= (1 << 12)
      when :auto_enter_mldp_mode
        bits |= (1 << 11)
      when :mldp_without_status
        bits |= (1 << 10)
      else
        raise "Invalid Supported feature (SR): #{setting}"
      end
    end
    fmt = sprintf("%08x", bits)
    puts "fmt = #{fmt}"
    return false unless write_and_verify("SR,#{fmt}", 'AOK')
    fmt
  end

  def server_services(settings)
    bits = 0
    settings.each do |setting|
      case setting
      when :device_information
        bits |= (1 << 31)
      when :battery
        bits |= (1 << 30)
      when :heart_rate
        bits |= (1 << 29)
      when :health_thermometer
        bits |= (1 << 28)
      when :glucose
        bits |= (1 << 27)
      when :blood_pressure
        bits |= (1 << 26)
      when :running_speed_cadence
        bits |= (1 << 25)
      when :cycling_speed_cadence
        bits |= (1 << 24)
      when :current_time
        bits |= (1 << 23)
      when :next_dst_change
        bits |= (1 << 22)
      when :reference_time_update
        bits |= (1 << 21)
      when :link_loss
        bits |= (1 << 20)
      when :immediate_alert
        bits |= (1 << 19)
      when :tx_power
        bits |= (1 << 18)
      when :alert_notification
        bits |= (1 << 17)
      when :phone_alert_status
        bits |= (1 << 16)
      when :scan_parameters
        bits |= (1 << 14)
      when :user_defined_private_service
        bits |= (1)
      else
        raise "Invalid Server Service (SS): #{setting}"
      end
    end
    fmt = sprintf("%08x", bits)
    puts "fmt = #{fmt}"
    return false unless write_and_verify("SR,#{fmt}", 'AOK')
    fmt
  end

  def set_connection(interval, latency, timeout)
    settings = []
    [interval, latency, timeout].each do |setting|
      if setting.is_a? String
        settings << setting.to_i(16)
      else
        settings << setting
      end
    end
    fmt = settings.collect{|s| sprintf("%04x", s)}
    return false unless write_and_verify("ST,#{fmt.join(',')}", 'AOK')
    fmt.join(',')
  end

  def scan(mode = :start)
    x = mode == :start ? "F" : "X"
    return false unless write_and_verify("#{x}", 'AOK')
    @data
  end

  def bond(mode = :bond)
    x = mode == :bond ? "B" : "U"
    return false unless write_and_verify("#{x}", 'AOK')
  end

  def toggle_echo
    write_and_verify('+', 'AOK')
  end

  def advertise(mode = :start)
    x = mode == :start ? "A" : "Y"
    return false unless write_and_verify("#{x}", 'AOK')
  end

  def reboot
    return false unless write_and_verify("R", 'AOK')
    @data
  end

  def connect(id)
    return false unless write_and_verify("E,0,#{id}", 'Connected')
  end

  def reconnect
    write_and_return('E')
  end

  def disconnect
    return false unless write_and_return("K")
  end

  def read_battery
    write_and_return('CURV,2A19')
  end

  alias_method :v,  :version
  alias_method :sr, :supported_features
  alias_method :ss, :server_services
  alias_method :st, :set_connection
end
