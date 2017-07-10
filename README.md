# ami.cr

crystal library that interacts with the asterisk manager interface (AMI) asyncronously sending actions and reciving events

## Installation

add to shard.yml

```yml
dependencies:
  ami:
    github: edersohe/ami.cr
    branch: master
```

## Usage

### Connect With asterisk manager ingterface

```crystal
ami = AMI.open("127.0.0.1", 5038)
```

### Create Handler

```
def print_event_handler(event : AMI::Message)
    p event.to_s         # AMI message format
    p event.to_h         # To hash
    p event.to_json      # To json
end
```

### Send action

```crystal
ami.action("login", username: "MyUsername", secret: "MyPassword", events: "all").send
ami.action("originate", channel: "PJSIP/6001", context: "from-internal", exten: 100, priority: 1).send
```

### Send action and handle response - in this case print response

```crystal
ami.action("login", username: "MyUsername", secret: "MyPassword", events: "all", handler: ->print_event_handler(AMI::Message)).send

ami.action("originate", channel: "PJSIP/6001", context: "from-internal", exten: 100, priority: 1, handler: ->print_event_handler(AMI::Message)).send
```

### Handle incoming events

```crystal
ami.add_pattern_handler("Event: ContactStatus\r\n", ->print_event_handler(AMI::Message))
ami.add_pattern_handler("Event: Hangup\r\n", ->print_event_handler(AMI::Message))
ami.add_pattern_handler("Event: DialEnd\r\n", ->print_event_handler(AMI::Message))
ami.add_pattern_handler("Event: DeviceStateChange(.*\r\n)*State: NOT_INUSE", ->print_event_handler(AMI::Message))
```

## Contributing

1. Fork it ( https://github.com/edersohe/ami.cr/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [edersohe](https://github.com/edersohe) Eder Sosa - creator, maintainer
