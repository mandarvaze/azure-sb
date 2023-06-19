# frozen_string_literal: true

require 'time'
require 'uri'
require 'openssl'
require 'base64'
require 'net/http'
require 'json'

class ServiceBus
  def initialize(logger)
    @logger = logger
  end

  def get_auth_token(sb_name, queue_name, sas_name, sas_value)
    uri = URI.encode_www_form_component("https://#{sb_name}.servicebus.windows.net/#{queue_name}")
    sas = sas_value.encode('utf-8')
    expiry = (Time.now + 2_000).to_i.to_s
    string_to_sign = "#{uri}\n#{expiry}".encode('utf-8')
    signed_hmac_sha256 = OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha256'), sas, string_to_sign)
    signature = URI.encode_www_form_component(Base64.strict_encode64(signed_hmac_sha256))

    "SharedAccessSignature sr=#{uri}&sig=#{signature}&se=#{expiry}&skn=#{sas_name}"
  end

  def peek_msg(url, auth_token)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.path)

    request['Authorization'] = auth_token

    http.request(request)
  end

  def delete_msg(url, auth_token)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'

    request = Net::HTTP::Delete.new(uri.path)

    request['Authorization'] = auth_token

    http.request(request)
  end

  def unlock_msg(url, auth_token)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'

    request = Net::HTTP::Put.new(uri.path)

    request['Authorization'] = auth_token

    http.request(request)
  end

  def process_peek_msg(peek_url, token)
    resp = peek_msg(peek_url, token)
    if resp.code == '204'
      @logger.info 'No message in the queue'
    else
      headers = resp.each_header.to_h
      @logger.debug "Headers: #{headers}"
      if headers.key?('brokerproperties')
        prop = JSON.parse(headers['brokerproperties'])

        lock_token = prop['LockToken']
        seq_number = prop['SequenceNumber']
        msg_id = prop['MessageId']
        delivery_count = prop['DeliveryCount']

        @logger.info "Message: #{resp.body}"
        @logger.debug "Lock Token: #{lock_token}"
        @logger.debug "Message ID: #{msg_id}"
        @logger.debug "Sequence Number: #{seq_number}"
        @logger.debug "Delivery Count: #{delivery_count}"

        [lock_token, msg_id, delivery_count, resp.body]
      else
        @logger.error 'brokerproperties header missing'
        [nil, nil, nil, resp.body]
      end
    end
  end
end
