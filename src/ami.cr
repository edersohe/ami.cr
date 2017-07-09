require "socket"
require "secure_random"
require "logger"

module AMI

  alias Event = Hash(String, String)
  alias Handler = Proc(Event, Nil)
  alias Handlers = Hash(String, Handler)
  alias Variables = Hash(String, String)

  @@log = Logger.new(STDOUT)
  @@log.level = Logger::Severity.from_value((ENV["LOG_LEVEL"]? || "1").to_i)
  @@client : TCPSocket = TCPSocket.allocate
  @@handlers = Handlers.new

  def self.log : Logger
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

  def self.open(host : String, port : Int32, reconnect : Bool = false) : Class
    loop do
      begin
        @@client = TCPSocket.new(host, port)
        sleep(1)
        read_event("\r\n")
        spawn do
          loop do
            read_event
          end
        end
        break
      rescue ex : Errno
        log.error(ex, "connect")
        if !reconnect
          break
        end
        sleep(10)
      end
    end
    AMI
  end

  def self.close : Nil
    @@client.close
  end

  def self.to_event(stream : String) : Event
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

  def self.read_event(delimiter : String = "\r\n\r\n") : Nil
    stream = @@client.gets(delimiter, chomp=true)
    if stream
      log.debug("\r\n#{stream}\r\n", "read_event")
      @@handlers.each_key do |key|
        if /#{key}/ === stream
          @@handlers[key].call(to_event(stream))
          if key.index("Response: (.*\r\n)*ActionID: (.*\r\n)*")
            @@handlers.delete(key)
          end
        end
      end
    end
  end

  def self.add_pattern_handler(pattern : String, handler : Handler) : Nil
      @@handlers[pattern] = handler
  end

  def self.send(message : String) : Nil
    log.debug("\r\n#{message}", "send_action")
    @@client << "#{message}\r\n"
  end

  def self.action(name : String,
             actionid : String = gen_id,
             variables : Variables = Variables.new,
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
    send(message)
    actionid
  end

end

