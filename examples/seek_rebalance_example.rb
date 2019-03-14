#!/usr/bin/env ruby
require 'optparse'
require 'ostruct'
require 'rdkafka'

params = {}
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: seek_rebalance_example.rb [options]"
  opts.on("-bSERVER", "--bootstrap-server=SERVER", "Bootstrap server. Defaults to localhost:9092")
  opts.on("-gID", "--group=ID", "[Required] Consumer group ID")
  opts.on("-tTOPIC_NAME", "--topic=TOPIC_NAME", "[Required] Name of Topic to subscribe to")
  opts.on("-sOFFSET", "--start-offset=OFFSET",
    "Start Offset. If unset, will not seek on start", Integer)
  opts.on("-eOFFSET", "--end-offset=OFFSET",
    "End Offset. If set it will seek to 0 on reaching this offset", Integer)
  opts.on("-wSECONDS", "--wait=SECONDS",
    "Number of seconds to wait between each message. Defaults to 1", Float)
  opts.on("-h", "--help") do
    puts opts
    exit
  end
end
optparse.parse!(into: params)

params[:"bootstrap-server"] ||= "localhost:9092"
params[:"wait"] ||= 1
if !params.has_key?(:group) || !params.has_key?(:topic)
  puts optparse.help
  exit 1
end

c = Rdkafka::Config.new(
  "bootstrap.servers": params[:"bootstrap-server"],
  "group.id": params[:group],
).consumer(rebalance_cb: ->(consumer, err, tpl) {
  puts "Consumer group #{params[:group]} rebalanced: #{err}"
  case err.code
  when :assign_partitions
    start_offset = params[:"start-offset"]
    unless start_offset.nil?
      tpl.each do |topic, partitions|
        partitions.each do |partition|
          puts "Assigning partition #{partition.partition} of #{topic} to #{start_offset}"
          partition.offset = start_offset
        end
      end
    end
    consumer.assign(tpl)
  when :revoke_partitions
    consumer.assign(nil)
  else
    consumer.assign(nil)
  end
})

trap("QUIT") { c.close }
trap("INT") { c.close }
trap("TERM") { c.close }

c.subscribe(params[:topic])
puts "Subscribed to #{params[:topic]}"

end_offset = params[:"end-offset"]
c.each do |message|
  puts "Got #{message.topic}/#{message.partition}@#{message.offset} #{message.payload}"
  if !end_offset.nil? && message.offset >= end_offset
    puts "Seeking back to 0 for #{message.topic}, #{message.partition}"
    c.seek(message.topic, message.partition, 0, 250)

    puts "Commiting the updated offsets immediately"
    tpl = Rdkafka::Consumer::TopicPartitionList.new
    tpl.add_topic_and_partitions_with_offsets(message.topic, {message.partition => 0})
    c.commit(tpl)
  end

  # Sleep 1 second to slow down the consumption so it is easier to follow.
  # Not needed in the real code.
  sleep params[:"wait"]
end

puts "Done"
