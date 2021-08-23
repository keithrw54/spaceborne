require 'airborne'
require 'spaceborne/version'
require 'rest-client'
require 'byebug'
require 'json'

# module for apitesting with spaceborne
module Spaceborne
  def json?(headers)
    headers.key?('Content-Type') &&
      headers['Content-Type'].include?('application/json')
  end

  def add_time
    "TIME: #{Time.now.strftime('%d/%m/%Y %H:%M')}\n"
  end

  def add_request
    if @request_body
      "REQUEST: #{response.request.method.upcase} #{response.request.url}\n"\
      "  HEADERS:\n#{JSON.pretty_generate(response.request.headers)}\n"\
      "  PAYLOAD:\n#{@request_body}\n"
    else
      ''
    end
  end

  def add_response
    "\nRESPONSE: #{response.code}\n"\
    "  HEADERS:\n#{JSON.pretty_generate(response.headers)}\n"\
    << response_body
  end

  def response_body
    return '' if response.request.method.casecmp('head').zero?

    if json?(response.headers)
      "  JSON_BODY\n#{JSON.pretty_generate(json_body)}\n"
    else
      "  BODY\n#{response.body}\n"
    end
  end

  def request_info(str = "\n")
    str << add_time << add_request << add_response
    str
  end

  def wrap_request
    yield
  rescue Exception => e
    raise e unless response

    raise RSpec::Expectations::ExpectationNotMetError, e.message + request_info
  end
end

# monkeypatch Airborne
module Airborne
  def decode_body
    if response.headers[:content_encoding]&.include?('gzip')
      Zlib::Inflate.new(32 + Zlib::MAX_WBITS).inflate(response.body)
    else
      response.body
    end
  end

  def json_body
    @json_body ||= JSON.parse(decode_body, symbolize_names: true)
  rescue StandardError
    raise InvalidJsonError, 'Api request returned invalid json'
  end

  # spaceborne enhancements
  module RestClientRequester
    def body?(method)
      case method
      when :post, :patch, :put
        true
      else
        false
      end
    end

    def split_options(options)
      local = {}
      local[:nonjson_data] = options.dig(:headers, :nonjson_data)
      options[:headers].delete(:nonjson_data) if local[:nonjson_data]
      local[:is_hash] = options[:body].is_a?(Hash)
      local[:proxy] = options.dig(:headers, :use_proxy)
      local
    end

    def calc_headers(options, local)
      headers = base_headers.merge(options[:headers] || {})
      headers[:no_restclient_headers] = true
      return headers unless local[:is_hash]

      headers.delete('Content-Type') if options[:nonjson_data]
      headers
    end

    def handle_proxy(_options, local)
      return unless local[:proxy]

      RestClient.proxy = local[:proxy]
    end

    def calc_body(options, local)
      return '' unless options[:body]

      if local[:nonjson_data] || !local[:is_hash]
        options[:body]
      else
        options[:body].to_json
      end
    end

    def send_restclient(method, url, body, headers)
      if body?(method)
        RestClient.send(method, url, body, headers)
      else
        RestClient.send(method, url, headers)
      end
    end

    def pre_request(options)
      @json_body = nil
      local_options = split_options(options)
      handle_proxy(options, local_options)
      hdrs = calc_headers(options, local_options)
      @request_body = calc_body(options, local_options)
      [hdrs, @request_body]
    end

    def make_request(method, url, options = {})
      hdrs, body = pre_request(options)
      send_restclient(method, get_url(url), body, hdrs)
    rescue RestClient::ServerBrokeConnection => e
      raise e
    rescue RestClient::Exception => e
      if [301, 302].include?(e.response&.code)
        e.response.&follow_redirection
      else
        e.response
      end
    end

    private

    def base_headers
      { 'Content-Type' => 'application/json' }
        .merge(Airborne.configuration.headers || {})
    end
  end

  # Extend airborne's expectations
  module RequestExpectations
    # class used for holding an optional path
    class OptionalPathExpectations
      def initialize(string)
        @string = string
      end

      def to_s
        @string.to_s
      end
    end

    def do_process_json(part, json)
      json = process_json(part, json)
    rescue StandardError
      raise PathError,
            "Expected #{json.class}\nto be an object with property #{part}"
    end

    def call_with_relative_path(data, args)
      if args.length == 2
        get_by_path(args[0], data) do |json_chunk|
          yield(args[1], json_chunk)
        end
      else
        yield(args[0], data)
      end
    end

    def exception_path_adder(args, body)
      yield
    rescue RSpec::Expectations::ExpectationNotMetError, Airborne::ExpectationError => e
      e.message << "\nexpect arguments: #{args}\ndata element: #{body}"
      raise e
    end

    def expect_json_types(*args)
      call_with_relative_path(json_body, args) do |param, body|
        exception_path_adder(args, body) do
          expect_json_types_impl(param, body)
        end
      end
    end

    def expect_json(*args)
      call_with_relative_path(json_body, args) do |param, body|
        exception_path_adder(args, body) do
          expect_json_impl(param, body)
        end
      end
    end

    def expect_header_types(*args)
      call_with_relative_path(response.headers, args) do |param, body|
        exception_path_adder(args, body) do
          expect_json_types_impl(param, body)
        end
      end
    end

    def expect_header(*args)
      call_with_relative_path(response.headers, args) do |param, body|
        exception_path_adder(args, body) do
          expect_json_impl(param, body)
        end
      end
    end

    def optional(data)
      if data.is_a?(Hash)
        OptionalHashTypeExpectations.new(data)
      else
        OptionalPathExpectations.new(data)
      end
    end
  end

  # extension to handle hash value checking
  module PathMatcher
    def handle_container(json, &block)
      case json.class.name
      when 'Array'
        expect_all(json, &block)
      when 'Hash'
        json.each { |k, _v| yield json[k] }
      else
        raise ExpectationError, "expected array or hash, got #{json.class.name}"
      end
    end

    def handle_type(type, path, json, &block)
      case type
      when '*'
        handle_container(json, &block)
      when '?'
        expect_one(path, json, &block)
      else
        yield json
      end
    end

    def make_sub_path_optional(path, sub_path)
      if path.is_a?(Airborne::OptionalPathExpectations)
        Airborne::OptionalPathExpectations.new(sub_path)
      else
        sub_path
      end
    end

    def iterate_path(path)
      raise PathError, "Invalid Path, contains '..'" if /\.\./ =~ path.to_s

      parts = path.to_s.split('.')
      parts.each_with_index do |part, index|
        use_part = make_sub_path_optional(path, part)
        yield(parts, use_part, index)
      end
    end

    def shortcut_validation(path, json)
      return true if json.nil? && path.is_a?(Airborne::OptionalPathExpectations)

      ensure_array_or_hash(path, json)
      false
    end

    def get_by_path(path, json, type: false, &block)
      iterate_path(path) do |parts, part, index|
        if %w[* ?].include?(part.to_s)
          return if shortcut_validation(path, json)

          type = part
          walk_with_path(type, index, path, parts, json, &block) && return if index < parts.length.pred

          next
        end
        json = do_process_json(part.to_s, json)
      end
      handle_type(type, path, json, &block)
    end

    def ensure_array_or_hash(path, json)
      return if json.instance_of?(Array) || json.instance_of?(Hash)

      raise RSpec::Expectations::ExpectationNotMetError,
            "Expected #{path} to be array or hash, got #{json.class}"\
            ' from JSON response'
    end

    def walk_with_path(type, index, path, parts, json, &block)
      last_error = nil
      item_count = json.length
      error_count = 0
      json.each do |element|
        begin
          sub_path = parts[(index.next)...(parts.length)].join('.')
          get_by_path(make_sub_path_optional(path, sub_path), element, &block)
        rescue Exception => e
          last_error = e
          error_count += 1
        end
        ensure_match_all(last_error) if type == '*'
        ensure_match_one(path, item_count, error_count) if type == '?'
      end
    end
  end
end
