# frozen_string_literal: true

require 'rails_helper'

describe AptrustStatusJob do
  let(:client) { instance_double(Aptrust::Client) }
  let!(:submission) do
    AptrustSubmission.create!(scope_type: 'collection', scope_id: 'col1', collection_id: 'col1', status: 'submitted', sid: 'sid-1')
  end
  let!(:bag) { submission.bags.create!(media_object_id: 'mo1', bag_name: 'Avalon-mo1', status: 'submitted') }

  before do
    allow(Settings.aptrust).to receive(:enabled).and_return(true)
    allow(Aptrust::Client).to receive(:new).and_return(client)
  end

  it 'tracks in-flight state' do
    allow(client).to receive(:submission_status).with('sid-1').and_return('state' => 'pending-ingest')
    allow(client).to receive(:bag_status).with('Avalon-mo1').and_return('submission' => 'sid-1', 'state' => 'pending-ingest')
    described_class.perform_now
    expect(submission.reload.status).to eq 'submitted'
    expect(submission.remote_state).to eq 'pending-ingest'
    expect(bag.reload.remote_state).to eq 'pending-ingest'
  end

  it 'completes the submission and its bags' do
    allow(client).to receive(:submission_status).with('sid-1').and_return('state' => 'complete')
    allow(client).to receive(:bag_status).and_return('submission' => 'sid-1', 'state' => 'complete')
    described_class.perform_now
    expect(submission.reload.status).to eq 'complete'
    expect(submission.completed_at).to be_present
    expect(bag.reload.status).to eq 'complete'
  end

  it 'ignores bag status from a later submission of the same bag' do
    allow(client).to receive(:submission_status).and_return('state' => 'pending-ingest')
    allow(client).to receive(:bag_status).and_return('submission' => 'sid-2', 'state' => 'error')
    described_class.perform_now
    expect(bag.reload.status).to eq 'submitted'
  end
end
