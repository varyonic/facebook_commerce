require 'webmock/rspec'

RSpec.describe FacebookCommerce do
  let(:access_token) { SecureRandom.hex(16) }
  let(:cms_id) { rand 0..99999 }
  let(:config) { { cms_id: cms_id, access_token: access_token } }
  let(:endpoint) { "https://graph.facebook.com" }
  subject { described_class.new(config) }

  describe described_class::OrderApi do
    let(:order_id) { '123' }

    describe '#list_orders' do
      before do
        stub_request(:get, "#{endpoint}/#{cms_id}/commerce_orders?access_token=#{access_token}&state=CREATED")
          .to_return(status: 200, body: JSON.generate(data: 'orders'))
      end
      
      it 'returns the orders' do
        expect(subject.list_orders(state: 'CREATED')).to eq('orders')
      end
    end

    describe '#get_order_details' do
      before do
        stub_request(:get, "#{endpoint}/#{order_id}?access_token=#{access_token}")
          .to_return(status: 200, body: JSON.generate(id: order_id))
      end

      it 'returns the order' do
        expect(subject.get_order_details(order_id)).to eq('id' => order_id)
      end
    end
  end

  describe described_class::AcknowledgementApi do
    let(:order_id) { '123' }

    describe '#associate_app' do
      before do
        stub_request(:post, "#{endpoint}/#{cms_id}/order_management_apps")
               .with(body: "access_token=#{access_token}")
          .to_return(status: 200, body: JSON.generate(success: true))
      end

      it 'returns the result' do
        expect(subject.associate_app).to eq('success' => true)
      end
    end

    describe '#acknowledge_order' do
      before do
        stub_request(:post, "#{endpoint}/#{order_id}/acknowledge_order")
          .to_return(status: 200, body: JSON.generate(state: 'IN_PROGRESS'))
      end

      it 'returns the result' do
        expect(subject.acknowledge_order(order_id)).to eq('state' => 'IN_PROGRESS')
      end
    end
  end

  describe described_class::FulfillmentApi do
    let(:order_id) { '123' }

    describe '#attach_shipment' do
      before do
        stub_request(:post, "#{endpoint}/#{order_id}/shipments")
          .to_return(status: 200, body: JSON.generate(success: true))
      end

      it 'returns the result' do
        expect(subject.attach_shipment(order_id, [], '')).to eq('success' => true)
      end
    end
  end

  describe described_class::CancellationRefundApi do
    let(:order_id) { '123' }

    describe '#cancel_order' do
      before do
        stub_request(:post, "#{endpoint}/#{order_id}/cancellations")
          .to_return(status: 200, body: JSON.generate(success: true))
      end

      it 'returns the result' do
        expect(subject.cancel_order(order_id)).to eq('success' => true)
      end
    end

    describe '#refund_order' do
      before do
        stub_request(:post, "#{endpoint}/#{order_id}/refunds")
          .to_return(status: 200, body: JSON.generate(success: true))
      end

      it 'returns the result' do
        expect(subject.refund_order(order_id, 'REFUND_REASON_OTHER')).to eq('success' => true)
      end
    end
  end

  describe described_class::ReturnApi do
    let(:order_id) { '123' }

    describe '#create_return' do
      before do
        stub_request(:post, "#{endpoint}/#{order_id}/returns")
          .with(body: /items=%5B/)
          .to_return(status: 200, body: JSON.generate(id: '1234567890'))
      end

      it 'returns the result' do
        expect(subject.create_return(order_id, [], 'RETURN_REASON_OTHER', '', '')).to eq('id' => '1234567890')
      end
    end

    describe '#update_return' do
      let(:return_id) { '123' }

      before do
        stub_request(:post, "#{endpoint}/#{return_id}/update_return")
          .to_return(status: 200, body: JSON.generate(success: true))
      end

      it 'returns the result' do
        expect(subject.update_return(return_id, 'ACCEPT_RETURN')).to eq('success' => true)
      end
    end
  end

  describe FacebookCommerce::Api::UnexpectedHttpResponse do
    let(:response_without_body) { double('response', message: 'Bad Request', code: '400', body: nil) }
    let(:response_with_empty_body) { double('response', message: 'Bad Request', code: '400', body: '') }
    let(:response_with_error_msg) { 
      double('response', 
        message: 'Bad Request', 
        code: '400', 
        body: JSON.generate({ error: { error_user_msg: 'We were unable to approve this return request' } })
      )
    }
    let(:response_with_invalid_json) { double('response', message: 'Bad Request', code: '400', body: 'invalid json') }

    it 'uses response message when no body is present' do
      error = FacebookCommerce::Api::UnexpectedHttpResponse.new(response_without_body)
      expect(error.message).to eq('Bad Request')
    end

    it 'uses response message when body is empty' do
      error = FacebookCommerce::Api::UnexpectedHttpResponse.new(response_with_empty_body)
      expect(error.message).to eq('Bad Request')
    end

    it 'appends error_user_msg when present in response body' do
      error = FacebookCommerce::Api::UnexpectedHttpResponse.new(response_with_error_msg)
      expect(error.message).to eq('Bad Request: We were unable to approve this return request')
    end

    it 'uses response message when JSON parsing fails' do
      error = FacebookCommerce::Api::UnexpectedHttpResponse.new(response_with_invalid_json)
      expect(error.message).to eq('Bad Request')
    end
  end

  describe 'error handling in API responses' do
    let(:bad_request_response) do
      double('response',
        message: 'Bad Request',
        code: '400',
        body: JSON.generate({ error: { error_user_msg: 'We were unable to approve this return request' } })
      )
    end

    it 'raises UnexpectedHttpResponse with error_user_msg when API returns 400' do
      api = FacebookCommerce::Api.new(config)
      
      expect {
        api.send(:fail_unless_expected_response, bad_request_response, Net::HTTPSuccess)
      }.to raise_error(FacebookCommerce::Api::UnexpectedHttpResponse, 'Bad Request: We were unable to approve this return request')
    end
  end
end
