require "socket"
require "secure_random"
require "logger"

module AMI
  alias Event = Hash(String, String)
  alias Handler = Proc(Event, Nil)

  @@log = Logger.new(STDOUT)
  @@log.level = Logger::Severity.from_value((ENV["LOG_LEVEL"]? || "1").to_i)

  def self.log : Logger
    @@log
  end

  def self.gen_id : String
    "#{Time.utc_now.epoch_ms}-#{SecureRandom.hex(10)}"
  end

  def self.info_handler(event : Event) : Nil
    log.info("\r\n#{event}\r\n", "info_handler")
  end

  def self.dummy_handler(event : Event) : Nil
  end

  class Client

    @client = TCPSocket.allocate

    def initialize(host : String, port : Int32)
      begin
        @client = TCPSocket.new(host, port)
      rescue ex : Errno
        AMI.log.fatal(ex, "intialize")
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
        AMI.log.debug("\r\n#{stream}\r\n", "read_event")
        @handlers.each_key do |key|
          if stream && /#{key}/ === stream
            @handlers[key].call(parse_event(stream))
            if key.index("Response: (.*\r\n)*ActionID: (.*\r\n)*")
              @handlers.delete(key)
            end
          end
        end
      end
    end

    def add_pattern_handler(pattern : String, handler : AMI::Handler) : Nil
        @handlers[pattern] = handler
    end

    def send_action(name : String,
                    actionid : String = AMI.gen_id,
                    variables : Hash(String, String) = {} of String => String,
                    handler : AMI::Handler | Nil = nil,
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
      AMI.log.debug("\r\n#{message}", "send_action")
      @client << "#{message}\r\n"
      actionid
    end
  end
end
