# encoding ascii-8bit

require 'rubyserial'

class RN4020

  def open_serial(port, baud = 115_200,  bits = 8, parity = :none)
    @serialport = Serial.new(port, baud, bits, parity)
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

  def read(timeout = 0.1)
    buf = ''
    cutoff = Time.now + timeout
    loop do
      byte = @serialport.getbyte
      buf << byte if byte
      break if Time.now > cutoff
      break if byte == "\n"
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
    return false unless write('V')
    read()
  end

  def factory_default(type = :partial)
    param = type == :partial ? 1 : 2
    return false unless write_and_verify("SF,#{param}", 'AOK')
    true
  end

  def baud(rate)
    return false unless write_and_verify("SF,#{rate}", 'AOK')
    rate.to_s
  end

  def serialized_name(name)
    write_and_verify("S-,#{name}", 'AOK')
  end

  def model(mdl)
    write_and_verify("SDM,#{mdl}", 'AOK')
  end

  def manufacturer(mf)
    write_and_verify("SDN,#{mf}", 'AOK')
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
    fmt = bits.to_s(16)
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
    fmt = bits.to_s(16)
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
  end

  def bond(mode = :bond)
    x = mode == :bond ? "B" : "U"
    return false unless write_and_verify("#{x}", 'AOK')
  end

  def advertise(mode = :start)
    x = mode == :start ? "A" : "Y"
    return false unless write_and_verify("#{x}", 'AOK')
  end

  def reboot
    return false unless write_and_verify("R", 'AOK')
  end

  alias_method :v,  :version
  alias_method :sr, :supported_features
  alias_method :ss, :server_services
  alias_method :st, :set_connection
end
