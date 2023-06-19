#!/usr/bin/env ruby
# frozen_string_literal: true

require './lib/service_bus'
require 'logger'
require 'json'

logger = Logger.new($stdout)
logger.level = ENV.fetch('LOGLEVEL', 'DEBUG')

sb_name = ENV.fetch('SB_NAMESPACE')
queue_name = ENV.fetch('QUEUE_NAME', 'test_queue')
sas_name = ENV.fetch('SAS_NAME', 'RootManageSharedAccessKey')
sas_value = ENV.fetch('SAS_VALUE')
max_delivery_count = ENV.fetch('MAX_DELIEVERY_COUNT', 10)
process_dead_letter = ENV.fetch('PROCESS_DLQ', 'false').downcase == 'true'
delete_message = ENV.fetch('DELETE_MESSAGE', 'false').downcase == 'true'

sb = ServiceBus.new(logger)

queue_name = "#{queue_name}/$DeadLetterQueue" if process_dead_letter
token = sb.get_auth_token(sb_name, queue_name, sas_name, sas_value)
logger.debug "Auth Token: #{token}"

peek_url = "https://#{sb_name}.servicebus.windows.net/#{queue_name}/messages/head"

lock_token, msg_id, delivery_count, msg = sb.process_peek_msg(peek_url, token)

message = JSON.parse(msg)
if !delivery_count.nil? && delivery_count >= max_delivery_count
  logger.fatal "Message with WebhookId will be going to DLQ : #{message['WebhookId']}"
end

if msg_id.nil? || lock_token.nil?
  logger.info 'Message ID or Lock Token missing, unable to unlock or delete the message'
else
  delete_or_unlock_url = "https://#{sb_name}.servicebus.windows.net/#{queue_name}/messages/#{msg_id}/#{lock_token}"
  logger.debug "Delete OR Unlock URL:  #{delete_or_unlock_url}"

  if delete_message
    logger.info 'Deleting the message from the queue'
    resp = sb.delete_msg(delete_or_unlock_url, token)
  else
    logger.info 'Unlocking the message'
    resp = sb.unlock_msg(delete_or_unlock_url, token)
  end

  logger.debug "Response Code: #{resp.code}"
  logger.debug "Response Body: #{resp.body}"
end
