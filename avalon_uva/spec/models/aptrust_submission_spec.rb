# frozen_string_literal: true

require 'rails_helper'

describe AptrustSubmission do
  def create_submission(status)
    described_class.create!(scope_type: 'collection', scope_id: 'col1', collection_id: 'col1', status: status)
  end

  describe '.in_progress_for_collection?' do
    it 'is true while any submission for the collection is not finished' do
      create_submission('complete')
      create_submission('restoring')
      expect(described_class.in_progress_for_collection?('col1')).to be true
      expect(described_class.in_progress_for_collection?('col2')).to be false
    end

    it 'is false once submissions are finished' do
      create_submission('complete')
      create_submission('error')
      expect(described_class.in_progress_for_collection?('col1')).to be false
    end
  end

  describe '#fail!' do
    it 'records the error on the submission and its unfinished bags' do
      submission = create_submission('staging')
      done = submission.bags.create!(media_object_id: 'a', bag_name: 'Avalon-a', status: 'complete')
      pending = submission.bags.create!(media_object_id: 'b', bag_name: 'Avalon-b')
      submission.fail!(Aptrust::Error.new('boom'))
      expect(submission.reload.status).to eq 'error'
      expect(submission.error_message).to eq 'Aptrust::Error: boom'
      expect(pending.reload.status).to eq 'error'
      expect(done.reload.status).to eq 'complete'
    end
  end

  it 'names bags with the configured prefix' do
    expect(described_class.bag_name_for('mo1')).to eq "#{Settings.aptrust.name_prefix}-mo1"
  end

  describe '#collection_name' do
    it 'is the scope and the collection name' do
      allow(Admin::Collection).to receive(:find).with('col1').and_return(double(name: 'Virginia  Folklore '))
      expect(create_submission('requested').collection_name).to eq 'Collection: Virginia Folklore'
    end

    it 'uses the title for a media object submission' do
      allow(MediaObject).to receive(:find).with('mo1').and_return(double(title: 'Field recordings'))
      submission = described_class.create!(scope_type: 'media_object', scope_id: 'mo1', collection_id: 'col1')
      expect(submission.collection_name).to eq 'Media object: Field recordings'
    end

    it 'fits the aptrust-submit column' do
      allow(Admin::Collection).to receive(:find).with('col1').and_return(double(name: 'x' * 100))
      expect(create_submission('requested').collection_name.length).to eq described_class::COLLECTION_NAME_LIMIT
    end

    it 'falls back to the id when the collection is gone' do
      allow(Admin::Collection).to receive(:find).with('col1').and_raise(ActiveFedora::ObjectNotFoundError)
      expect(create_submission('requested').collection_name).to eq 'Collection: col1'
    end
  end
end
