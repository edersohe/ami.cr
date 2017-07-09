require "socket"
require "secure_random"
require "logger"


module AMI

  EOL = "\r\n"
  EOE = "\r\n\r\n"

  alias Event = Hash(String, String)
  alias Handler = Proc(Event, Nil)
  alias Handlers = Hash(String, Handler)
  alias Variables = Hash(String, String)

  @@log = Logger.new(STDOUT)
  @@log.level = Logger::Severity.from_value((ENV["LOG_LEVEL"]? || "1").to_i)
  @@log.formatter = Logger::Formatter.new do |severity, datetime, progname, message, io|
    label = severity.unknown? ? "ANY" : severity.to_s
    io << EOL << label[0] << ", [" << datetime << " #" << Process.pid << "] "
    io << label.rjust(5) << " -- " << progname << ": " << EOL << message.chomp
  end
  @@client : TCPSocket = TCPSocket.allocate
  @@handlers = Handlers.new

  def self.log : Logger
    @@log
  end

  def self.client : TCPSocket
    @@client
  end

  def self.handlers : Handlers
    @@handlers
  end

  def self.gen_id : String
    "#{Time.utc_now.epoch_ms}-#{SecureRandom.hex(5)}"
  end

  def self.info_handler(event : Event) : Nil
    log.info(event, "info_handler")
  end

  def self.dummy_handler(event : Event) : Nil
  end

  class Action
    def initialize(@id : String, @message : String)
    end

    def id
      @id
    end

    def message
      @message
    end

    def to_s
      @message
    end

    def send : Nil
      AMI.log.debug(message, "send")
      AMI.client << message << EOL
    end
  end

  def self.to_h(event : String) : Event
    h = Hash(String, String).new
    unknown = 0
    event.split(EOL).each do |line|
      begin
        key, value = line.split(": ", 2)
        h[key] = value
      rescue
        unknown += 1
        h = {"UnknownField#{unknown}" => line}
      end
    end
    h
  end

  def self.open(host : String, port : Int32, reconnect : Bool = false) : Class
    loop do
      begin
        @@client = TCPSocket.new(host, port)
        sleep(1)
        read_event(EOL)
        spawn do
          loop do
            read_event
          end
        end
        break
      rescue ex : Errno
        log.error(ex, "open")
        if !reconnect
          break
        end
        sleep(10)
      end
    end
    AMI
  end

  def self.close : Nil
    client.close
  end

  def self.dispatch_event_handler(event : String)
    handlers.each_key do |key|
      if /#{key}/ === event
        handlers[key].call(to_h(event))
        if key.index("Response: (.*\r\n)*ActionID: (.*\r\n)*")
          handlers.delete(key)
        end
      end
    end
  end

  def self.read_event(delimiter : String = EOE) : Nil
    event = client.gets(delimiter, chomp=true)
    if event
      log.debug(event, "read_event")
      dispatch_event_handler(event)
    end
  end

  def self.add_pattern_handler(pattern : String, handler : Handler) : Nil
      handlers[pattern] = handler
  end

  def self.action(name : String,
             actionid : String = gen_id,
             variables : Variables = Variables.new,
             handler : Handler | Nil = nil,
             **params) : Action
    message = "action: #{name.downcase + EOL}"
    message += "actionid: #{actionid + EOL}"
    params.each do |key, value|
      message += "#{key.to_s.downcase}: #{value.to_s + EOL}"
    end
    variables.each do |key, value|
      message += "Variable: #{key.downcase}=#{value + EOL}"
    end
    if handler
      add_pattern_handler("Response: (.*\r\n)*ActionID: #{actionid}(.*\r\n)*", handler)
    end
    Action.new(actionid, message)
  end

end
