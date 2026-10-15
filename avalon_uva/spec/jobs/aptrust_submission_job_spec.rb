# frozen_string_literal: true

require 'rails_helper'

describe AptrustSubmissionJob do
  let(:client) { instance_double(Aptrust::Client) }
  let(:collection) { FactoryBot.create(:collection, unit: Avalon::ControlledVocabulary.find_by_name(:units).first) }
  let(:master_file) { double(id: 'mf1') }
  let(:media_object) { double(id: 'mo1', sections: [master_file], published?: true) }
  let(:s3_object) { double(bucket_name: 'archive', key: 'mf1.mov') }
  let(:source) { Aptrust::SourceResolver::Source.new(s3_object: s3_object, size: 10, filename: 'mf1.mov') }
  let(:submission) do
    AptrustSubmission.create!(scope_type: 'collection', scope_id: collection.id, collection_id: collection.id, requested_by: 'manager')
  end

  before do
    allow(Aptrust::Client).to receive(:new).and_return(client)
    allow(MediaObject).to receive(:find).with('mo1').and_return(media_object)
    allow(Aptrust::SourceResolver).to receive(:resolve).with(master_file).and_return(source)
    allow(described_class).to receive(:perform_later)
    allow(described_class).to receive(:set).and_return(described_class)
  end

  describe 'planning' do
    before { allow_any_instance_of(Admin::Collection).to receive(:media_object_ids).and_return(['mo1']) }

    it 'creates a bag for each item that needs preserving' do
      allow(AptrustBag).to receive(:needs_submission?).and_return(true)
      allow(Aptrust::Glacier).to receive(:available?).and_return(true)
      described_class.perform_now(submission.id)
      expect(submission.bags.pluck(:bag_name)).to eq ["#{Settings.aptrust.name_prefix}-mo1"]
      expect(submission.reload.status).to eq 'staging'
    end

    it 'finishes without submitting when nothing has changed' do
      allow(AptrustBag).to receive(:needs_submission?).and_return(false)
      described_class.perform_now(submission.id)
      expect(submission.reload.status).to eq 'complete'
      expect(submission.message).to match(/No new or changed published items/)
    end

    it 'skips unpublished items' do
      allow_any_instance_of(Admin::Collection).to receive(:media_object_ids).and_return(%w[mo1 mo2])
      allow(MediaObject).to receive(:find).with('mo2').and_return(double(id: 'mo2', sections: [master_file], published?: false))
      allow(AptrustBag).to receive(:needs_submission?).and_return(true)
      allow(Aptrust::Glacier).to receive(:available?).and_return(true)
      described_class.perform_now(submission.id)
      expect(submission.bags.pluck(:media_object_id)).to eq ['mo1']
    end

    it 'splits large collections into several submissions' do
      allow_any_instance_of(Admin::Collection).to receive(:media_object_ids).and_return(%w[mo1 mo1b])
      allow(MediaObject).to receive(:find).with('mo1b').and_return(double(id: 'mo1b', sections: [master_file], published?: true))
      allow(AptrustBag).to receive(:needs_submission?).and_return(true)
      allow(Aptrust::Glacier).to receive(:available?).and_return(true)
      allow(Settings.aptrust).to receive(:max_bags_per_submission).and_return(1)
      submission_id = submission.id
      expect { described_class.perform_now(submission_id) }.to change(AptrustSubmission, :count).by(1)
      expect(AptrustSubmission.for_collection(collection.id).map { |s| s.bags.count }).to eq [1, 1]
    end
  end

  describe 'restoring' do
    before { submission.bags.create!(media_object_id: 'mo1', bag_name: 'Avalon-mo1') }

    it 'requests a Glacier restore and checks again later' do
      allow(Aptrust::Glacier).to receive(:available?).and_return(false)
      expect(Aptrust::Glacier).to receive(:request_restore).with(s3_object)
      described_class.perform_now(submission.id)
      expect(submission.reload.status).to eq 'restoring'
      expect(described_class).to have_received(:set).with(wait: Settings.aptrust.restore_poll.to_i.seconds)
    end
  end

  describe 'staging and initiating' do
    let(:builder) { instance_double(Aptrust::BagBuilder, manifest: { 'a' => 'b' }, byte_size: 10) }

    before do
      submission.update!(status: 'staging')
      submission.bags.create!(media_object_id: 'mo1', bag_name: 'Avalon-mo1')
      allow(Aptrust::BagBuilder).to receive(:new).and_return(builder)
      allow(AptrustBag).to receive(:source_modified_at).and_return(1.day.ago)
    end

    it 'registers, stages each bag, then initiates with the staged bag folders' do
      expect(client).to receive(:register).with(collection: "Collection: #{collection.name}").and_return('sid' => 'sid-1', 'bucket' => 'inbound', 'path' => 'cid/sid-1')
      expect(builder).to receive(:build!).with(media_object)
      described_class.perform_now(submission.id)
      expect(submission.bags.first.status).to eq 'staged'

      expect(client).to receive(:initiate).with(sid: 'sid-1', bag_folders: ['Avalon-mo1']).and_return('status' => 'validating')
      described_class.perform_now(submission.id)
      expect(submission.reload.status).to eq 'submitted'
      expect(submission.remote_state).to eq 'validating'
    end

    it 'removes a bag that fails to stage and fails the submission when nothing was staged' do
      allow(client).to receive(:register).and_return('sid' => 'sid-1', 'bucket' => 'inbound', 'path' => 'cid/sid-1')
      allow(builder).to receive(:build!).and_raise(Aptrust::Error, 'no source')
      expect(builder).to receive(:remove!)
      described_class.perform_now(submission.id)
      expect(submission.bags.first.reload.status).to eq 'error'

      described_class.perform_now(submission.id)
      expect(submission.reload.status).to eq 'error'
    end
  end
end
