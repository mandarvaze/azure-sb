# frozen_string_literal: true

require 'time'
require 'uri'
require 'openssl'
require 'base64'
require 'net/http'
require 'json'
require 'logger'

logger = Logger.new($stdout)
logger.level = ENV.fetch('LOGLEVEL', 'DEBUG')

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
      if headers.key?(:brokerproperties)
        prop = JSON.parse(headers['brokerproperties'])

        lock_token = prop['LockToken']
        seq_number = prop['SequenceNumber']
        msg_id = prop['MessageId']

        @logger.debug "Lock Token: #{lock_token}"
        @logger.debug "Message ID: #{msg_id}"
        @logger.debug "Sequence Number: #{seq_number}"

        [lock_token, msg_id, seq_number]
      else
        @logger.error 'brokerproperties header missing'
        [nil, nil, nil]
      end
    end
  end
end

sb_name = ENV.fetch('SB_NAMESPACE')
queue_name = ENV.fetch('QUEUE_NAME', 'test_queue')
sas_name = ENV.fetch('SAS_NAME', 'RootManageSharedAccessKey')
sas_value = ENV.fetch('SAS_VALUE')

sb = ServiceBus.new(logger)
token = sb.get_auth_token(sb_name, queue_name, sas_name, sas_value)
logger.debug "Auth Token: #{token}"
peek_url = "https://#{sb_name}.servicebus.windows.net/#{queue_name}/messages/head"

lock_token, msg_id, = sb.process_peek_msg(peek_url, token)

if msg_id.nil? || lock_token.nil?
  logger.info 'Message ID or Lock Token missing, unable to unlock or delete the message'
else
  delete_or_unlock_url = "https://#{sb_name}.servicebus.windows.net/#{queue_name}/messages/#{msg_id}/#{lock_token}"
  logger.debug "Delete OR Unlock URL:  #{delete_or_unlock_url}"

  resp = sb.unlock_msg(delete_or_unlock_url, token)
  logger.debug "Response Code: #{resp.code}"
  logger.debug "Response Body: #{resp.body}"

  # resp = sb.delete_msg(delete_or_unlock_url, token)
  # logger.debug "Response Code: #{resp.code}"
  # logger.debug "Response Body: #{resp.body}"
end
