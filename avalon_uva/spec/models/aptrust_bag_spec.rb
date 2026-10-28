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

  describe 'archive dates' do
    def bag_for(submission, media_object_id:, status:, updated_at:)
      bag = submission.bags.create!(media_object_id: media_object_id, bag_name: "Avalon-#{media_object_id}-#{status}-#{updated_at.to_i}", status: status)
      bag.update_columns(updated_at: updated_at)
      bag
    end

    it 'uses the latest completed bag for an item' do
      older = 5.days.ago.change(usec: 0)
      newer = 1.day.ago.change(usec: 0)
      bag_for(submission, media_object_id: 'mo1', status: 'complete', updated_at: older)
      bag_for(submission, media_object_id: 'mo1', status: 'complete', updated_at: newer)
      bag_for(submission, media_object_id: 'mo1', status: 'submitted', updated_at: Time.current)
      bag_for(submission, media_object_id: 'mo1', status: 'error', updated_at: Time.current)

      expect(described_class.last_archived_at_for_item('mo1')).to be_within(1.second).of(newer)
    end

    it 'ignores an item that was submitted or failed but never completed' do
      bag_for(submission, media_object_id: 'mo1', status: 'submitted', updated_at: 1.hour.ago)
      bag_for(submission, media_object_id: 'mo1', status: 'error', updated_at: 1.hour.ago)

      expect(described_class.last_archived_at_for_item('mo1')).to be_nil
    end

    it 'scopes a collection date to that collection' do
      archived_at = 2.days.ago.change(usec: 0)
      other_archived_at = 1.hour.ago.change(usec: 0)
      other = AptrustSubmission.create!(scope_type: 'collection', scope_id: 'col2', collection_id: 'col2')
      bag_for(submission, media_object_id: 'mo1', status: 'complete', updated_at: archived_at)
      bag_for(other, media_object_id: 'mo2', status: 'complete', updated_at: other_archived_at)

      expect(described_class.last_archived_at_for_collection('col1')).to be_within(1.second).of(archived_at)
      expect(described_class.last_archived_at_for_collection('col2')).to be_within(1.second).of(other_archived_at)
      expect(described_class.last_archived_at_for_collection('col3')).to be_nil
    end

    it 'returns no sentence without a date' do
      expect(described_class.archive_note(nil, 'item')).to be_nil
    end

    it 'formats the public sentence from the archive date' do
      archived_at = Time.utc(2026, 10, 28, 15, 0, 0)
      expect(described_class.archive_note(archived_at, 'collection')).to eq(
        "This collection was last archived to APTrust on #{I18n.l(archived_at.in_time_zone.to_date, format: :long)}."
      )
    end
  end
end
