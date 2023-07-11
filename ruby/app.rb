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
requeue_message = ENV.fetch('REQUEUE_MESSAGE', 'false').downcase == 'true'

sb = ServiceBus.new(logger)

queue_name = "#{queue_name}/$DeadLetterQueue" if process_dead_letter
token = sb.get_auth_token(sb_name, queue_name, sas_name, sas_value)
logger.debug "Auth Token: #{token}"

peek_url = "https://#{sb_name}.servicebus.windows.net/#{queue_name}/messages/head"
send_url = "https://#{sb_name}.servicebus.windows.net/#{queue_name}/messages"

lock_token, msg_id, sb_delivery_count, msg = sb.process_peek_msg(peek_url, token)
return if lock_token.nil? || msg_id.nil?

message = JSON.parse(msg)
# If message does not have DeliveryCount, use one supplied by ServiceBus.
delivery_count = message['DeliveryCount'].nil? ? sb_delivery_count : message['DeliveryCount'].to_i + 1
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
  elsif requeue_message
    logger.info 'Sending the message back to the queue'
    # Set/update the delivery count.
    message['DeliveryCount'] = delivery_count
    # Add delay of at least 1 minute (in case delivery count is zero)
    time_to_enqueue = Time.now + 60 * delivery_count + 60
    resp = sb.send_scheduled_msg(send_url, token, time_to_enqueue, message)
    if resp.code == '201' # Successfully requeued, now delete original message
      logger.info 'Deleting the original message from the queue'
      resp = sb.delete_msg(delete_or_unlock_url, token)
    end
  else
    logger.info 'Unlocking the message'
    resp = sb.unlock_msg(delete_or_unlock_url, token)
  end

  logger.debug "Response Code: #{resp.code}"
  logger.debug "Response Body: #{resp.body}"
end
