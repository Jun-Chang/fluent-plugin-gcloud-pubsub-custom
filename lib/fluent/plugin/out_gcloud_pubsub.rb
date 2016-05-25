require 'gcloud'

module Fluent
  class GcloudPubSubOutput < Fluent::BufferedOutput
    Fluent::Plugin.register_output('gcloud_pubsub', self)

    config_set_default :buffer_type,                'lightening'
    config_set_default :flush_interval,             1
    config_set_default :try_flush_interval,         0.05
    config_set_default :buffer_chunk_records_limit, 900
    config_set_default :buffer_chunk_limit,         9437184
    config_set_default :buffer_queue_limit,         64

    config_param :project,                 :string,  :default => nil
    config_param :topic,                   :string,  :default => nil
    config_param :key,                     :string,  :default => nil
    config_param :autocreate_topic,        :bool,    :default => false
    config_param :max_records_per_request, :integer, :default => 1000

    unless method_defined?(:log)
      define_method("log") { $log }
    end

    unless method_defined?(:router)
      define_method("router") { Fluent::Engine }
    end

    def configure(conf)
      super

      raise Fluent::ConfigError, "'project' must be specified." unless @project
      raise Fluent::ConfigError, "'topic' must be specified." unless @topic
      raise Fluent::ConfigError, "'key' must be specified." unless @key
    end

    def start
      super

      pubsub = (Gcloud.new @project, @key).pubsub
      @client = pubsub.topic @topic, autocreate: @autocreate_topic
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def write(chunk)
      messages = []
      log.debug "Chunk record_counter:#{chunk.record_counter.to_s} size:#{chunk.size.to_s}"

      chunk.msgpack_each do |tag, time, record|
        messages << record.to_json
      end

      if messages.length > 0
        messages.each_slice(@max_records_per_request).each do |msg|
          publish msg
        end
      end
    rescue => e
      log.error "unexpected error", :error=>$!.to_s
      log.error_backtrace
      raise e
    end

    def publish(messages)
      @client.publish do |batch|
        messages.each do |m|
          batch.publish m
        end
      end
    end
  end
end
