# frozen_string_literal: true

RSpec.describe FacebookCommerce do
  it "has a version number" do
    expect(FacebookCommerce::VERSION).not_to be nil
  end

  let(:config) { { cms_id: '123', access_token: 'abc' } }

  describe described_class::OrderApi do
    subject { described_class.new(config) }

    describe '#list_orders' do
      let(:params) { { state: 'CREATED' } }
      let(:response) { { data: 'orders' }.to_json }
      
      before do
        allow(subject).to receive(:send_request).and_return(response)
      end
      
      it 'returns the orders' do
        expect(subject.list_orders(params)).to eq('orders')
      end
    end

    describe '#get_order_details' do
      let(:order_id) { '123' }
      let(:response) { { id: order_id }.to_json }
      
      before do
        allow(subject).to receive(:send_request).and_return(response)
      end

      it 'returns the order' do
        expect(subject.get_order_details(order_id)).to eq('id' => order_id)
      end
    end
  end

  describe described_class::AcknowledgementApi do
    subject { described_class.new(config) }

    describe '#associate_app' do
      let(:response) { { success: true }.to_json }

      before do
        allow(subject).to receive(:send_request).and_return(response)
      end

      it 'returns the result' do
        expect(subject.associate_app).to eq('success' => true)
      end
    end

    describe '#acknowledge_order' do
      let(:order_id) { '123' }
      let(:response) { { state: 'IN_PROGRESS' }.to_json }
      
      before do
        allow(subject).to receive(:send_request).and_return(response)
      end

      it 'returns the result' do
        expect(subject.acknowledge_order(order_id)).to eq('state' => 'IN_PROGRESS')
      end
    end
  end

  describe described_class::FulfillmentApi do
    subject { described_class.new(config) }

    describe '#attach_shipment' do
      let(:order_id) { '123' }
      let(:response) { { success: true }.to_json }
      
      before do
        allow(subject).to receive(:send_request).and_return(response)
      end

      it 'returns the result' do
        expect(subject.attach_shipment(order_id, [], '')).to eq('success' => true)
      end
    end
  end

  describe described_class::CancellationRefundApi do
    subject { described_class.new(config) }

    describe '#cancel_order' do
      let(:order_id) { '123' }
      let(:response) { { success: true }.to_json }
      
      before do
        allow(subject).to receive(:send_request).and_return(response)
      end

      it 'returns the result' do
        expect(subject.cancel_order(order_id)).to eq('success' => true)
      end
    end

    describe '#refund_order' do
      let(:order_id) { '123' }
      let(:response) { { success: true }.to_json }
      
      before do
        allow(subject).to receive(:send_request).and_return(response)
      end

      it 'returns the result' do
        expect(subject.refund_order(order_id, 'REFUND_REASON_OTHER')).to eq('success' => true)
      end
    end
  end

  describe described_class::ReturnApi do
    subject { described_class.new(config) }

    describe '#create_return' do
      let(:order_id) { '123' }
      let(:response) { { id: '1234567890' }.to_json }
      
      before do
        allow(subject).to receive(:send_request).and_return(response)
      end

      it 'returns the result' do
        expect(subject.create_return(order_id, [], 'RETURN_REASON_OTHER', '', '')).to eq('id' => '1234567890')
      end
    end

    describe '#update_return' do
      let(:return_id) { '123' }
      let(:response) { { success: true }.to_json }
      
      before do
        allow(subject).to receive(:send_request).and_return(response)
      end

      it 'returns the result' do
        expect(subject.update_return(return_id, 'ACCEPT_RETURN')).to eq('success' => true)
      end
    end
  end
end
