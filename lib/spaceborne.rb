require 'airborne'
require 'spaceborne/version'
require 'rest-client'
require 'byebug'
require 'json'

# module for apitesting with spaceborne
module Spaceborne
  def json?(headers)
    headers.key?(:content_type) &&
      headers[:content_type].include?('application/json')
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
    "RESPONSE: #{response.code}\n"\
    "  HEADERS:\n#{JSON.pretty_generate(response.headers)}\n"\
    << response_body
  end

  def response_body
    return '' if response.request.method.casecmp('head').zero?
    str = if json?(response.headers)
            "  JSON_BODY\n#{JSON.pretty_generate(json_body)}\n"
          else
            "  BODY\n#{response.body}\n"
          end
    str
  end

  def request_info(str = "\n")
    str << add_time << add_request << add_response
    str
  end

  def wrap_request
    yield
  rescue Exception => e
    raise e unless response
    e.message << request_info
    raise e
  end
end

# monkeypatch Airborne
module Airborne
  def json_body
    @json_body ||= JSON.parse(response.body, symbolize_names: true)
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

    def make_request(method, url, options = {})
      @json_body = nil
      local_options = split_options(options)
      handle_proxy(options, local_options)
      hdrs = calc_headers(options, local_options)
      @request_body = calc_body(options, local_options)
      send_restclient(method, get_url(url), @request_body, hdrs)
    rescue RestClient::Exception => e
      e.response
    end

    private

    def base_headers
      { content_type: 'application/json' }
        .merge(Airborne.configuration.headers || {})
    end
  end

  # Extend airborne's expectations
  module RequestExpectations
    def call_with_relative_path(data, args)
      if args.length == 2
        get_by_path(args[0], data) do |json_chunk|
          yield(args[1], json_chunk)
        end
      else
        yield(args[0], data)
      end
    end

    def exception_path_adder(path)
      yield
    rescue Airborne::ExpectationError => e
      e.message << " at location #{path}"
      raise e
    end

    def expect_json_types(*args)
      call_with_relative_path(json_body, args) do |param, body|
        exception_path_adder(args[0]) do
          expect_json_types_impl(param, body)
        end
      end
    end

    def expect_json(*args)
      call_with_relative_path(json_body, args) do |param, body|
        exception_path_adder(args[0]) do
          expect_json_impl(param, body)
        end
      end
    end

    def expect_header_types(*args)
      call_with_relative_path(response.headers, args) do |param, body|
        exception_path_adder(args[0]) do
          expect_json_types_impl(param, body)
        end
      end
    end

    def expect_header(*args)
      call_with_relative_path(response.headers, args) do |param, body|
        exception_path_adder(args[0]) do
          expect_json_impl(param, body)
        end
      end
    end
  end

  # extension to handle hash value checking
  module PathMatcher
    def get_by_path(path, json, &block)
      raise PathError, "Invalid Path, contains '..'" if /\.\./ =~ path
      type = false
      parts = path.to_s.split('.')
      parts.each_with_index do |part, index|
        if %w[* ?].include?(part)
          ensure_array_or_hash(path, json)
          type = part
          if index < parts.length.pred
            walk_with_path(type, index, path, parts, json, &block) && return
          end
          next
        end
        begin
          json = process_json(part, json)
        rescue StandardError
          raise PathError,
                "Expected #{json.class}\nto be an object with property #{part}"
        end
      end
      if type == '*'
        case json.class.name
        when 'Array'
          expect_all(json, &block)
        when 'Hash'
          json.each do |k, _v|
            yield json[k]
          end
        end
      elsif type == '?'
        expect_one(path, json, &block)
      else
        yield json
      end
    end

    def ensure_array_or_hash(path, json)
      return if json.class == Array || json.class == Hash
      raise RSpec::Expectations::ExpectationNotMetError,
            "Expected #{path} to be array or hash, got #{json.class}"\
            ' from JSON response'
    end
  end
end
