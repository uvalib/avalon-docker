# frozen_string_literal: true

# One media object staged as one bag folder within an AptrustSubmission
class AptrustBag < ApplicationRecord
  # pending -> staging -> staged -> submitted -> complete | error | abandoned
  STATUSES = %w[pending staging staged submitted complete error abandoned].freeze
  TERMINAL = %w[complete error abandoned].freeze

  belongs_to :submission, class_name: 'AptrustSubmission', foreign_key: :aptrust_submission_id, inverse_of: :bags

  validates :status, inclusion: { in: STATUSES }
  validates :media_object_id, :bag_name, presence: true

  # Maps an aptrust-submit bag state to a local bag status
  def self.status_for_remote(state)
    case state
    when 'complete' then 'complete'
    when 'error' then 'error'
    when 'abandoned' then 'abandoned'
    else 'submitted'
    end
  end

  # Whether a media object should be included in a new submission: it has never been preserved,
  # or it has changed since it was last successfully preserved.
  # This is the single place that decides the delta sent to APTrust.
  def self.needs_submission?(media_object, modified_at = source_modified_at(media_object))
    last = where(media_object_id: media_object.id, status: 'complete').order(created_at: :desc).first
    return true if last.nil? || last.source_modified_at.nil? || modified_at.nil?

    modified_at > last.source_modified_at
  end

  # Latest modification time across a media object, its master files and their supplemental files
  def self.source_modified_at(media_object)
    objects = [media_object, *media_object.sections]
    times = objects.map { |obj| obj.modified_date rescue nil }
    times += objects.flat_map { |obj| obj.supplemental_files.map(&:updated_at) }
    times.compact.map { |t| t.to_time.utc }.max
  end
end
