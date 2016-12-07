require 'logger'

module Logging

  # This is the magical bit that gets mixed into your classes

  def logger
    Logging.logger
  end

  # Global, memoized, lazy initialized instance of a logger

  def self.logger
    @logger ||= Logger.new('log.log')
  end
end

class RN4020

  attr_reader :bta
  attr_reader :name
  attr_reader :role
  attr_reader :connected
  attr_reader :bonded
  attr_reader :ss
  attr_reader :found
  attr_reader :gain

  REBOOT = 'R,1'.freeze
  FULL_RESET = 'SF,2'.freeze
  SS = 'SS'.freeze
  SR = 'SR'.freeze
  CLEAN_PRIVATE_SERVICES = 'PZ'.freeze
  LIST_CLIENT_SERVICES = 'LC'.freeze
  LIST_SERVER_SERVICES = 'LS'.freeze
  SCAN = 'F'.freeze
  STOP_SCAN = 'X'.freeze
  BOND = 'B'.freeze
  UNBOND = 'U'.freeze
  DUMP = 'D'.freeze
  ADVERTISE = 'A'.freeze

  AOK = "AOK\r\n".freeze
  AOK_CONNECTED = "AOK\r\nConnected\r\n".freeze
  CMD = "CMD\r\n".freeze
  CONNECTED = "Connected\r\n".freeze
  SERVER_SERVICE = 'Server Service'.freeze
  BONDED = "Bonded\r\n".freeze
  SECURED = "Secured\r\n".freeze
  CONNECTION_END = "Connection End\r\n".freeze

  include Logging

  def debug_write(x)
#    p x.to_s.strip
#    return if x.to_s.strip.empty?
    self.logger.info("#{@id} << #{x}")
  end

  def debug_read(x)
    @debug_str << x unless x == "\n"
    return unless x == "\n"
#    return if x.to_s.strip.empty?
    self.logger.info("#{@id} >> #{@debug_str}")
    @debug_str = ''
  end

  def init_port(port, baud)
    count = 0
    loop do
      begin
        @port = Serial.new(port, baud, 8, :none)
        return true
      rescue RubySerial::Exception
        count += 1
        raise if count >= 5
        sleep 1
      end
    end
  end

  def initialize(id, port, baud = 115_200)
    @iterations = 180
    @debug_str = ''
    @id = id
    init_port(port, baud)
  end

  def write(x)
    @port.write(x + "\r")
    debug_write(x + "\r")
  end

  def write_and_receive(send, rcv)
    write(send)
    @read_buf = ''
    @iterations.times do |count|
      delay(:short)
      @read_buf << read
      break if @read_buf.include?(rcv)
      return false if count == 9
      delay(:short) unless send == REBOOT
      delay(:long) if send == REBOOT
    end
    true
  end

  def read
    buffer = ''
    loop do
      byte = @port.getbyte
      buffer << byte if byte
      debug_read(byte.chr) if byte
      break unless byte
    end
    buffer
  end

  def delay(duration = :long)
    sec = case duration
          when :short then 0.06
          when :long then 0.1
          else
            raise "Invalid duration in #delay"
          end
    sleep sec
  end

  def read_and_receive(rcv)
    @read_buf = ''
    @iterations.times do |retries|
      @read_buf << read
      break if @read_buf.include?(rcv)
      delay(:short)
      return false if retries == 59
    end
    true
  end

  def read_value(uuid)
    @read_buf = ''
    return nil unless write("CURV,#{uuid}")
    @iterations.times do |count|
      delay(:short)
      @read_buf << read
      break if @read_buf.include?(AOK)
      return nil if count == 9
    end
    /R,([0-9,a-f,A-F]*)\./.match(@read_buf)
    value = Regexp.last_match(1)
    value
  end

  def flush
    loop do
      byte = @port.getbyte
      break unless byte
    end
  end

  def full_reset
    write_and_receive(FULL_RESET, AOK)
  end

  def reboot
    write_and_receive(REBOOT, CMD)
  end

  def server_services(ss)
    write_and_receive("SS,#{ss}", AOK)
  end

  def options(sr)
    write_and_receive("SR,#{sr}", AOK)
  end

  def clean_private_services
    write_and_receive(CLEAN_PRIVATE_SERVICES, AOK)
  end

  def ps(uuid)
    write_and_receive("PS,#{uuid}", AOK)
  end

  def pc(uuid, attribs, size)
    write_and_receive("PC,#{uuid},#{attribs},#{size}", AOK)
  end

  def stop_scan
    write_and_receive(STOP_SCAN, AOK)
  end

  def dump_parse
    if /BTA=([0-9a-fA-F_]*)\r\nName=([a-zA-Z0-9_]*)\r\nRole=([a-zA-Z0-9_]*)\r\nConnected=([a-zA-Z0-9,]*)\r\nBonded=([0-9a-fA-F_,]*)\r\nServer Service=([0-9a-fA-F]*)\r\n/ =~ @read_buf
      @bta = Regexp.last_match(1)
      @name = Regexp.last_match(2)
      @role = Regexp.last_match(3)
      @connected = Regexp.last_match(4)
      @bonded = Regexp.last_match(5)
      @ss = Regexp.last_match(6)
      true
    else
      false
    end
  end

  def dump
#    3.times do
    success = write_and_receive(DUMP, SERVER_SERVICE)
    #  break if success
#      sleep 1
#    end
    dump_parse
    success
  end

  def connect(mac)
    write_and_receive("E,0,#{mac}", AOK)
  end

  def advertise
    write_and_receive(ADVERTISE, AOK)
  end

  def advertise_to_connect
    write_and_receive(ADVERTISE, AOK_CONNECTED)
  end

  def bond
    write_and_receive(BOND, BONDED)
  end

  def secure
    write_and_receive(BOND, SECURED)
  end

  def list_client_services
    write_and_receive(LIST_CLIENT_SERVICES, 'END')
  end

  def list_server_services
    write_and_receive(LIST_SERVER_SERVICES, 'END')
  end

  def disconnect
    write_and_receive('K', CONNECTION_END)
  end

  def write_reading(uuid, value)
    write_and_receive("SUW,#{uuid},#{value}", AOK)
  end

  def reconnect
    write('E')
  end

  def wait_for_connection
    read_and_receive(CONNECTED)
  end

  def wait_for_disconnect
    read_and_receive(CONNECTION_END)
  end

  def scan
    write(SCAN)
    @read_buf = ''
    @iterations.times do
      @read_buf << read
      if /AOK\r\n([0-9a-fA-F]{12},0),(-[0-9a-fA-F]{2})/ =~ @read_buf
        @found = Regexp.last_match(1)
        @gain = Regexp.last_match(2)
        return true
      end
      delay(:short)
    end
    false
  end

  def wake
    write_and_receive('.', "ERR\r\n")
  end

  def go_dormant
    write('O')
  end

  def unbond
    write_and_receive(UNBOND, AOK)
  end
end
