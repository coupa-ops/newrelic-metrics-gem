require 'restclient'
require 'json'
require 'uri'
require 'chronic'

module NewRelicMetrics
  class Configuration
    attr_accessor :api_key
    def initialize(api_key:nil,&block)
      @api_key=api_key
      yield(self) if block
    end
  end

  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  class RequestFailed < StandardError
  end

  class Client
    BASE = 'https://api.newrelic.com/v2'

    def initialize(config=nil)
      @config = config || NewRelicMetrics.configuration

      raise ArgumentError, "No API Key is configured" unless @config && @config.api_key
    end

    def names(application:nil, server:nil)
      raise ArgumentError, "Need to define either an application or server id" unless application || server
      raise ArgumentError, "Need to define either an application or server id, but not both" if application && server
      resource = application ? 'applications' : 'servers'
      resource_id = application || server
      get(resource, resource_id, "metrics")
    end

    def metrics(application:nil, server:nil, metrics:, range:{}, summarize: false)
      if range && range!={}
        raise ArgumentError, "Range must only contain a :to and :from time" unless range.keys.all?{|k| k==:to || k==:from }
        raise ArgumentError, "Range must contain a :from time" unless range.keys.include?(:from)
      end

      raise ArgumentError, "Need to define either an application or server id" unless application || server
      raise ArgumentError, "Need to define either an application or server id, but not both" if application && server

      resource = application ? 'applications' : 'servers'
      resource_id = application || server

      conditions = []

      metrics.keys.each {|name| conditions << "names[]=#{URI.encode(name)}" }
      metrics.values.flatten.each {|val| conditions << "values[]=#{URI.encode(val)}" }

      if range[:from]
        from_time = Chronic.parse(range[:from], context: :past)
        to_time = Chronic.parse(range[:to]) if range[:to]
        to_time ||= Time.now
        if from_time
          conditions << "from=#{from_time.getlocal('+00:00').iso8601}"
          conditions << "to=#{to_time.getlocal('+00:00').iso8601}"
        end
      end

      conditions << "summarize=true" if summarize

      query = conditions.join('&')
      get(resource, resource_id, "metrics/data", query)
    end

    private

    def get(resource, resource_id, path, query=nil)
      uri = URI.parse('https://api.newrelic.com/')
      uri.path = "/v2/#{resource}/#{resource_id}/#{path}.json"
      uri.query = query if query && query != ""

      puts uri.to_s

      begin
        response = RestClient.get(uri.to_s,'X-Api-Key'=>@config.api_key)
      rescue => ex
        if ex.response
          message = JSON.parse(ex.response).values.first['title']
          raise RequestFailed, message
        else
          raise RequestFailed, ex.message
        end
      end
    end
  end
end