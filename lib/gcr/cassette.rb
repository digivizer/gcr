class GCR::Cassette
  VERSION = 2

  attr_reader :reqs

  # Delete all recorded cassettes.
  #
  # Returns nothing.
  def self.delete_all
    Dir[File.join(GCR.cassette_dir, "*.json")].each do |path|
      File.unlink(path)
    end
  end

  # Initialize a new cassette.
  #
  # name - The String name of the recording, from which the path is derived.
  #
  # Returns nothing.
  def initialize(name)
    @path = File.join(GCR.cassette_dir, "#{name}.json")
    @reqs = []
  end

  # Does this cassette exist?
  #
  # Returns boolean.
  def exist?
    File.exist?(@path)
  end

  # Load this cassette.
  #
  # Returns nothing.
  def load
    data = JSON.parse(File.read(@path))

    if data["version"] != VERSION
      raise "GCR cassette version #{data["version"]} not supported"
    end

    @reqs = data["reqs"].map do |req, resp|
      [GCR::Request.from_hash(req), GCR::Response.from_hash(resp)]
    end
  end

  # Persist this cassette.
  #
  # Returns nothing.
  def save
    return if reqs.empty? && !GCR.save_empty_requests?

    File.open(@path, "w") do |f|
      f.write(JSON.pretty_generate(
        "version" => VERSION,
        "reqs" => reqs,
      ))
    end
  end

  # Record all GRPC calls made while calling the provided block.
  #
  # Returns nothing.
  def record(&blk)
    start_recording
    blk.call
  ensure
    stop_recording
  end

  # Play recorded GRPC responses.
  #
  # Returns nothing.
  def play(&blk)
    start_playing
    blk.call
  ensure
    stop_playing
  end

  def start_recording
    GCR.stub.class.class_eval do
      alias_method :orig_request_response, :request_response

      def request_response(*args, return_op: false, **kwargs)
        if return_op
          # capture the operation
          operation = orig_request_response(*args, return_op: return_op, **kwargs)

          # capture the response
          resp = orig_request_response(*args, return_op: false, **kwargs)

          req = GCR::Request.from_proto(*args)
          if GCR.cassette.reqs.none? { |r, _| r == req }
            GCR.cassette.reqs << [req, GCR::Response.from_proto(resp)]
          end

          # then return it
          operation
        else
          orig_request_response(*args, return_op: return_op, **kwargs).tap do |resp|
            req = GCR::Request.from_proto(*args)
            if GCR.cassette.reqs.none? { |r, _| r == req }
              GCR.cassette.reqs << [req, GCR::Response.from_proto(resp)]
            end
          end
        end
      end
    end
  end

  def stop_recording
    GCR.stub.class.class_eval do
      alias_method :request_response, :orig_request_response
    end
    save
  end

  def start_playing
    load

    GCR.stub.class.class_eval do
      alias_method :orig_request_response, :request_response

      def request_response(*args, return_op: false, **kwargs)
        req = GCR::Request.from_proto(*args)
        GCR.cassette.reqs.each do |other_req, resp|
          if req == other_req

            # check if our request wants an operation returned rather than the response
            if return_op
              # if so, collect the original operation
              operation = orig_request_response(*args, return_op: return_op, **kwargs)

              # hack the execute method to return the response we recorded
              operation.define_singleton_method(:execute) { return resp.to_proto }

              # then return it
              return operation
            else
              # otherwise just return the response
              return resp.to_proto
            end
          end
        end
        raise GCR::NoRecording
      end
    end
  end

  def stop_playing
    GCR.stub.class.class_eval do
      alias_method :request_response, :orig_request_response
    end
  end

  def [](req)
    reqs.find { |r| r == req }
  end

  def []=(req, resp)
    reqs << [req, resp]
  end
end
