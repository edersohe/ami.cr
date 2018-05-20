require "socket"
require "random"
require "logger"

RANDOM = Random.new

module AMI

  EOL = "\r\n"
  EOE = "\r\n\r\n"

  class Error < Exception
  end

  class Message

    def initialize(@string : String)
      @hash = Hash(String, String).new
    end

    def to_h : Hash(String, String)
      if @hash.empty?
        unknown = 0
        @string.chomp.split(EOL).each do |line|
          begin
            key, value = line.split(": ", 2)
            @hash[key.underscore] = value
          rescue
            unknown += 1
            @hash["unknown#{unknown}"] = line
          end
        end
      end
      @hash
    end

    def to_s
      @string
    end

    def to_json
      to_h.to_json
    end

    def log(severity : Logger::Severity, progname : String = "")
      AMI.log.log(severity, self, progname)
      self
    end

    def send : Nil
      AMI.send(@string)
      self
    end
  end

  alias Event = Channel(Message)
  alias Callback = Proc(Message, Nil)
  alias Handlers = Array(Tuple(String, Callback | Event, Bool, Tuple(Logger::Severity, String)))
  alias Variables = Hash(String, String)

  @@log = Logger.new(STDOUT)
  @@log.level = Logger::Severity.from_value((ENV["LOG_LEVEL"]? || "1").to_i)
  @@log.formatter = Logger::Formatter.new do |severity, datetime, progname, message, io|
    label = severity.unknown? ? "ANY" : severity.to_s
    io << EOL << label[0] << " [" << datetime.to_s("%F %T") << " #" << Process.pid
    io << "] " << progname << ": " << EOL << message.chomp
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
    "#{Time.utc_now.epoch_ms}-#{RANDOM.hex(5)}"
  end

  def self.dummy_handler(event : Message) : Nil
  end

  def self.open(host : String, port : Int32, username : String, secret : String, events : String = "all", debug : Bool = false) : AMI.class
    @@client = TCPSocket.new(host, port)
    sleep(1)
    receive(EOL)
    spawn do
      loop do
        receive
      end
    end
    login(username, secret, events, debug)
    if debug
      add_debug_handler
    end
    AMI
  end

  def self.login(username : String, secret : String, events : String, debug : Bool) : Nil
    action_id = gen_id
    channel = Event.new

    add_handler(
      "Response: (.*\r\n)*ActionID: #{action_id}(.*\r\n)*",
      channel,
      log: {Logger::INFO, "login"}
    )

    message = action(
      "login",
      action_id: action_id,
      username: username,
      secret: secret,
      events: events
    )

    if debug
      message.log(Logger::DEBUG, "debug send")
    end

    message.send

    if channel.receive.to_h["response"] != "Success"
      raise Error.new("Login error : Bad Credentials")
    end
  end

  def self.add_debug_handler : Nil
    add_handler(
      "(.*\r\n)*",
      permanent: true,
      log: {Logger::DEBUG, "debug"}
    )
  end

  def self.close : Nil
    client.close
  end

  def self.run : Nil
    sleep
  end

  def self.fire_handler(callback : Callback, message : Message) : Nil
    callback.call(message)
  end

  def self.fire_handler(event : Event, message : Message) : Nil
    event.send(message)
  end

  def self.dispatch_handler(event : String)
    handlers.each do |handler|
      if /#{handler[0]}/ === event
        message = Message.new(event)

        if handler[3][0] < Logger::UNKNOWN
          log.log(handler[3][0], message, handler[3][1] + " match " + handler[0].inspect)
        end

        fire_handler(handler[1], message)

        if !handler[2]
          handlers.delete(handler)
        end
      end
    end
  end

  def self.receive(delimiter : String = EOE) : Nil
    event = client.gets(delimiter, chomp=true)
    if event
      dispatch_handler(event)
    end
  end

  def self.send(message : String): Nil
    client << "#{message + EOL}"
  end

  def self.add_handler(pattern : String,
                       handler : Callback | Event = ->dummy_handler(Message),
                       permanent : Bool = false,
                       log : Tuple(Logger::Severity, String) = {Logger::UNKNOWN, ""}) : AMI.class
      handlers << {pattern, handler, permanent, log}
      AMI
  end

  def self.action(name : String,
                  action_id : String = gen_id,
                  variables : Variables = Variables.new,
                  **params) : Message
    action = "Action: #{name.camelcase + EOL}"
    action += "ActionID: #{action_id + EOL}"
    params.each do |key, value|
      action += "#{key.to_s.camelcase}: #{value.to_s + EOL}"
    end
    variables.each do |key, value|
      action += "Variable: #{key}=#{value + EOL}"
    end
    Message.new(action)
  end
end
