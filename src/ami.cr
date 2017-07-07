require "socket"
require "secure_random"
require "logger"

module Aliases
  alias Event = Hash(String, String)
  alias Handler = Proc(Event, Nil)
end


class AMI
  include Aliases

  @client = TCPSocket.allocate
  @@logger = Logger.new(STDOUT)
  @@logger.level = Logger::Severity.from_value((ENV["LOG_LEVEL"]? || "1").to_i)

  def initialize(host : String, port : Int32, logger : Logger = @@logger)
    @@logger = logger
    @@logger.level = Logger::Severity.from_value((ENV["LOG_LEVEL"]? || "1").to_i)

    begin
      @client = TCPSocket.new(host, port)
    rescue ex : Errno
      log.fatal(ex, "AMI::initialize")
      exit(1)
    end

    @handlers = {} of String => AMI::Handler

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

  def log : Logger
    @@logger
  end

  def self.log : Logger
    @@logger
  end

  def self.info_handler(event : AMI::Event) : Nil
      AMI.log.info("\r\n#{event}\r\n", "AMI::info_handler")
  end

  def self.dummy_handler(event : AMI::Event) : Nil
  end

  def parse_event(stream : String) : AMI::Event
    event = AMI::Event.new
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
      log.debug("\r\n#{stream}\r\n", "AMI::read_event")
      @handlers.each_key do |key|
        if stream && /#{key}/ === stream
          @handlers[key].call(parse_event(stream))
          if key.starts_with?("ActionID: ")
            @handlers.delete(key)
          end
        end
      end
    end
  end

  def add_pattern_handler(pattern : String, handler : AMI::Handler) : Nil
      @handlers[pattern] = handler
  end

  def send_action(name : String, **params, variables : Hash(String, String) = {} of String => String, handler : AMI::Handler | Nil = nil, id : String = "") : String
    id = id == "" ? SecureRandom.uuid : id
    action_id = "ActionID: #{name}-#{id}"
    message = "#{action_id}\r\naction: #{name}\r\n"
    params.each do |key, value|
      message += "#{key}: #{value}\r\n"
    variables.each do |key, value|
      message += "Variable: #{key}=#{value}\r\n"
    end
    if handler
      add_pattern_handler(action_id, handler)
    end
    log.debug("\r\n#{message}", "AMI::send_action")
    @client << "#{message}\r\n"
    id
  end
end
