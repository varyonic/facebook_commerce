# frozen_string_literal: true

require_relative "facebook_commerce/version"

require 'benchmark'
require 'json'
require 'logger'
require 'securerandom'

module FacebookCommerce
  BASE_URL = 'https://graph.facebook.com/'
  class Error < StandardError; end

  def self.configure(&block)
    yield @config
  end

  def config
    @config
  end

  class Api
    class UnexpectedHttpResponse < StandardError
      def initialize(response)
        message = response.message || response.code
        
        # Try to extract error_user_msg from Facebook API response
        if response.body && !response.body.empty?
          begin
            parsed_body = JSON.parse(response.body)
            error_user_msg = parsed_body.dig('error', 'error_user_msg')
            if error_user_msg
              message = "#{message}: #{error_user_msg}"
            end
          rescue JSON::ParserError
            # If JSON parsing fails, just use the original message
          end
        end
        
        super message
      end
    end
    
    attr_reader :access_token # See https://business.facebook.com/commerce_permission_wizard
    attr_reader :cms_id
    attr_accessor :logger

    # config[:cms_id]
    # config[:access_token]
    def initialize(config = super.config)
      @cms_id = config.fetch(:cms_id)
      @access_token = config.fetch(:access_token)
      @logger = config[:logger] || Logger.new(STDOUT)
    end

    protected

    def get(path, data = {})
      path = "#{path}?#{URI.encode_www_form(data.merge(access_token: access_token))}"
      JSON.parse(send_request('GET', BASE_URL + path))
    end

    def post(path, data = {})
      data.merge!(access_token: access_token)
      JSON.parse(send_request('POST', BASE_URL + path, data))
    end

    # Accepts hash of fields to send.
    # Returns response body if successful else raises exception.
    def send_request(method, path, fields = {})
      uri = URI(path)
      connection = https(uri)
      data = fields.to_a.map { |x| "#{x[0]}=#{x[1]}" }.join("&")
      response = log_request_response(method, uri, data) do |m, u, d|
        connection.send_request(m, u.to_s, d)
      end
      fail_unless_expected_response response, Net::HTTPSuccess
      response.body
    end

    def https(uri)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end
  
    # Log method, URI, data
    # Start timer.
    # Yield method, URI, data.
    # Log response and time taken.
    def log_request_response(method, uri, data = nil)
      logger.info "[#{self.class.name}] request = #{method} #{uri}#{data ? '?' + data : ''}"
      response = nil
      tms = Benchmark.measure do
        response = yield method, uri, data
      end
      logger.info("[#{self.class.name}] response (#{(tms.real*1000).round(3)}ms): #{response.inspect} #{response.body}")
      response
    end

    def fail_unless_expected_response(response, *allowed_responses)
      unless allowed_responses.any? { |allowed| response.is_a?(allowed) }
        logger.error "#{response.inspect}: #{response.body}"
        raise UnexpectedHttpResponse, response
      end
      response
    end
  end

  # https://developers.facebook.com/docs/commerce-platform/order-management/order-api
  class OrderApi < Api
    # By default the list_orders method will return orders in the CREATED state.
    # @option params updated_before [String] Unix timestamp
    # @option params updated_after [String] Unix timestamp
    # state The state of the order. The default is CREATED. FB_PROCESSING, IN_PROGRESS, COMPLETED
    def list_orders(params = {})
      get("#{cms_id}/commerce_orders", params).fetch('data')
    end

    # @param order_id [String]
    # @option params fields [String] Comma-separated list of fields to include in the response
    def get_order_details(order_id, params = {})
      get(order_id, params)
    end
  end

  # https://developers.facebook.com/docs/commerce-platform/order-management/acknowledgement-api
  class AcknowledgementApi < Api
    def associate_app
      post("#{cms_id}/order_management_apps")
    end

    def acknowledge_order(order_id, merchant_order_reference = nil)
      data = { idempotency_key: SecureRandom.uuid }
      data[:merchant_order_reference] = merchant_order_reference if merchant_order_reference
      post("#{order_id}/acknowledge_order", data)
    end
  end

  # https://developers.facebook.com/docs/commerce-platform/order-management/fulfillment-api
  class FulfillmentApi < Api
    # @param order_id [String] Facebook order ID
    # @param items [Array<Hash>] Array of item hashes (retailer_id|product_id, quantity)
    # @param tracking_info [Hash] Tracking information (carrier, tracking_number, shipping_method_name)
    def attach_shipment(order_id, items, tracking_info, external_shipment_id = nil)
      data = { 
        items: items.to_json,
        tracking_info: tracking_info.to_json,
        idempotency_key: SecureRandom.uuid
      }
      data[:external_shipment_id] = external_shipment_id if external_shipment_id

      post("#{order_id}/shipments", data)
    end
  end

  class CancellationRefundApi < Api
    # @param order_id [String] Facebook order ID
    # @return [Hash] Cancellation response, eg. { success: true}
    def cancel_order(order_id)
      data = { idempotency_key: SecureRandom.uuid }
      post("#{order_id}/cancellations", data)
    end

    # @param order_id [String] Facebook order ID
    # @param reason_code [String] Reason code for the refund, eg. 'REFUND_REASON_OTHER'
    # @param items [Array<Hash>] Item hashes (retailer_id|product_id, quantity), required if partial refund
    # @return [Hash] Refund response, eg. { success: true}
    def refund_order(order_id, reason_code, items = nil)
      data = { reason_code: reason_code, idempotency_key: SecureRandom.uuid }
      post("#{order_id}/refunds", data)
    end
  end

  class ReturnApi < Api
    # @param order_id [String] Facebook order ID
    # @param items [Array<Hash>] Array of item hashes (item_id|retailer_id, quantity, reason)
    # @param return_status [String] Reason code for the return,
    #   eg. 'REQUESTED', 'APPROVED', 'DISAPPROVED', 'REFUNDED', 'MERCHANT_MARKED_COMPLETED'
    # @return [Hash] Return response, eg. { id: '1234567890' }
    def create_return(order_id, items, return_status, return_message, merchant_return_id)
      data = {
        items: CGI.escape(JSON.generate items),
        return_status: return_status,
        return_message: return_message,
        merchant_return_id: merchant_return_id
      }
      post("#{order_id}/returns", data)
    end

    # @param return_id [String] Facebook return ID
    # @param update_event [String] Reason code for the return, 'ACCEPT_RETURN' or 'CLOSE_RETURN'
    # @option options [String] notes Notes for the return
    # @option options [String] merchant_return_id Merchant return ID
    # @option options [Array<Hash>] return_shipping_labels Array of shipping label hashes
    #         (carrier, service_name, tracking_number, file_handle, cost)
    def update_return(return_id, update_event, options = {})
      post("#{return_id}/update_return", options.merge(update_event: update_event))
    end
  end
end
