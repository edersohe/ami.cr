require "socket"
require "secure_random"
require "logger"

class AMI

  alias Event = Hash(String, String)
  alias Handler = Proc(Event, Nil)

  @@log = Logger.new(STDOUT)
  @@log.level = Logger::Severity.from_value((ENV["LOG_LEVEL"]? || "1").to_i)
  @handlers = {} of String => Handler

  def log : Logger
    @@log
  end

  def self.gen_id : String
    "#{Time.utc_now.epoch_ms}-#{SecureRandom.hex(10)}"
  end

  def self.info_handler(event : Event) : Nil
    @@log.info("\r\n#{event}\r\n", "info_handler")
  end

  def self.dummy_handler(event : Event) : Nil
  end

  def initialize(host : String, port : Int32, logger : Logger = @@log)
    @client = TCPSocket.allocate
    @handlers = {} of String => Handler
    @@log = logger

    begin
      @client = TCPSocket.new(host, port)
    rescue ex : Errno
      log.fatal(ex, "connect")
      exit(1)
    end

    sleep(1)
    read_event("\r\n")

    spawn do
      loop do
        read_event
      end
    end
  end

  def close : Nil
    @client.close
    exit(0)
  end

  def parse_event(stream : String) : Event
    event = Event.new
    begin
      stream.split("\r\n").each do |line|
        token = line.split(": ", 2)
        event[token[0]] = token[1]
      end
    rescue
      event = {"RawEvent" => stream}
    end
    event
  end

  def read_event(delimiter : String = "\r\n\r\n") : Nil
    stream = @client.gets(delimiter, chomp=true)
    if stream
      log.debug("\r\n#{stream}\r\n", "read_event")
      @handlers.each_key do |key|
        if /#{key}/ === stream
          @handlers[key].call(parse_event(stream))
          if key.index("Response: (.*\r\n)*ActionID: (.*\r\n)*")
            @handlers.delete(key)
          end
        end
      end
    end
  end

  def add_pattern_handler(pattern : String, handler : Handler) : Nil
      @handlers[pattern] = handler
  end

  def send_action(name : String,
                  actionid : String = AMI.gen_id,
                  variables : Hash(String, String) = {} of String => String,
                  handler : Handler | Nil = nil,
                  **params) : String
    message = "ActionID: #{actionid}\r\nAction: #{name.capitalize}\r\n"
    params.each do |key, value|
      message += "#{key.to_s.capitalize}: #{value}\r\n"
    end
    variables.each do |key, value|
      message += "Variable: #{key}=#{value}\r\n"
    end
    if handler
      add_pattern_handler("Response: (.*\r\n)*ActionID: #{actionid}(.*\r\n)*", handler)
    end
    log.debug("\r\n#{message}", "send_action")
    @client << "#{message}\r\n"
    actionid
  end
end
