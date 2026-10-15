# frozen_string_literal: true

require 'rails_helper'

describe Aptrust::Client do
  let(:settings) do
    double(client_id: 'cid-avalon-test', register_url: 'https://apts.example.com/register',
           submit_url: 'https://apts.example.com/submit', submission_status_url: 'https://apts.example.com/submission',
           bag_status_url: 'https://apts.example.com/bag', http_timeout: 5)
  end
  subject(:client) { described_class.new(settings) }

  it 'registers a submission' do
    stub = stub_request(:post, settings.register_url)
           .with(body: { cid: 'cid-avalon-test', collection: 'Avalon-abc' }.to_json)
           .to_return(body: { sid: 'sid-1', bucket: 'inbound', path: 'cid-avalon-test/sid-1' }.to_json)
    expect(client.register(collection: 'Avalon-abc')).to eq('sid' => 'sid-1', 'bucket' => 'inbound', 'path' => 'cid-avalon-test/sid-1')
    expect(stub).to have_been_requested
  end

  it 'initiates a submission with its bag folders' do
    stub_request(:post, settings.submit_url)
      .with(body: { cid: 'cid-avalon-test', sid: 'sid-1', bag_folders: %w[Avalon-1 Avalon-2] }.to_json)
      .to_return(body: { submission: 'sid-1', status: 'validating' }.to_json)
    expect(client.initiate(sid: 'sid-1', bag_folders: %w[Avalon-1 Avalon-2])['status']).to eq 'validating'
  end

  it 'raises the service error text on failure' do
    stub_request(:post, settings.submit_url).to_return(status: 400, body: 'bag folder mismatch')
    expect { client.initiate(sid: 'sid-1', bag_folders: []) }.to raise_error(Aptrust::Error, /400.*bag folder mismatch/)
  end

  it 'returns nil for an unknown submission' do
    stub_request(:get, "#{settings.submission_status_url}?sid=sid-x").to_return(status: 404, body: 'not found')
    expect(client.submission_status('sid-x')).to be_nil
  end

  it 'looks up bag status by bag name' do
    stub_request(:get, "#{settings.bag_status_url}?bid=Avalon-1")
      .to_return(body: { submission: 'sid-1', name: 'Avalon-1', state: 'pending-ingest' }.to_json)
    expect(client.bag_status('Avalon-1')['state']).to eq 'pending-ingest'
  end

  it 'explains missing configuration instead of making a request' do
    allow(settings).to receive(:register_url).and_return(nil)
    expect { client.register(collection: 'Avalon-abc') }.to raise_error(Aptrust::Error, /not configured \(missing service URL\)/)
  end
end
