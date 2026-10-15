# frozen_string_literal: true

require 'rails_helper'

describe AptrustBag do
  let(:submission) { AptrustSubmission.create!(scope_type: 'collection', scope_id: 'col1', collection_id: 'col1') }
  let(:media_object) { double(id: 'mo1') }
  let(:staged_at) { 2.days.ago.utc.change(usec: 0) }

  def preserved(status: 'complete')
    submission.bags.create!(media_object_id: 'mo1', bag_name: 'Avalon-mo1', status: status, source_modified_at: staged_at)
  end

  describe '.needs_submission?' do
    it 'is true for an item never preserved' do
      expect(described_class.needs_submission?(media_object, 1.day.ago)).to be true
    end

    it 'is true when the last preservation attempt failed' do
      preserved(status: 'error')
      expect(described_class.needs_submission?(media_object, staged_at)).to be true
    end

    it 'is false for an unchanged preserved item' do
      preserved
      expect(described_class.needs_submission?(media_object, staged_at)).to be false
    end

    it 'is true for an item changed since it was preserved' do
      preserved
      expect(described_class.needs_submission?(media_object, 1.hour.ago)).to be true
    end
  end

  describe '.status_for_remote' do
    it 'maps aptrust-submit bag states' do
      expect(described_class.status_for_remote('pending-ingest')).to eq 'submitted'
      expect(described_class.status_for_remote('complete')).to eq 'complete'
      expect(described_class.status_for_remote('error')).to eq 'error'
    end
  end
end
