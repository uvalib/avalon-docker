# frozen_string_literal: true

# A request to preserve Avalon content in APTrust via the uvalib aptrust-submit service.
# One submission maps to one aptrust-submit submission (sid) and holds one bag per media object.
class AptrustSubmission < ApplicationRecord
  SCOPES = %w[collection media_object].freeze
  # requested -> restoring -> staging -> submitted -> complete | incomplete | error | abandoned
  STATUSES = %w[requested restoring staging submitted complete incomplete error abandoned].freeze
  TERMINAL = %w[complete incomplete error abandoned].freeze
  # remote (aptrust-submit) submission states that end a submission
  REMOTE_TERMINAL = %w[complete incomplete error abandoned].freeze
  # aptrust-submit stores the submission name as VARCHAR(64)
  COLLECTION_NAME_LIMIT = 64

  has_many :bags, class_name: 'AptrustBag', dependent: :destroy

  validates :scope_type, inclusion: { in: SCOPES }
  validates :status, inclusion: { in: STATUSES }
  validates :scope_id, :collection_id, presence: true

  scope :in_progress, -> { where.not(status: TERMINAL) }
  scope :for_collection, ->(collection_id) { where(collection_id: collection_id) }
  scope :recent, -> { order(created_at: :desc) }

  def self.in_progress_for_collection?(collection_id)
    in_progress.for_collection(collection_id).exists?
  end

  def self.latest_for_collection(collection_id)
    for_collection(collection_id).recent.first
  end

  # Serialize submission requests for a collection so concurrent clicks cannot both pass the in-progress check
  def self.with_collection_lock(collection_id, &block)
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{connection.quote("aptrust-#{collection_id}")}))")
      block.call
    end
  end

  def self.bag_name_for(media_object_id)
    "#{Settings.aptrust.name_prefix}-#{media_object_id}"
  end

  def terminal?
    TERMINAL.include?(status)
  end

  # The submission name shown in aptrust-submit e.g. "Modern History of Virginia Winemaking collection"
  def collection_name
    "#{scope_label}".squish.truncate(COLLECTION_NAME_LIMIT, omission: '')
  end

  def fail!(error)
    message = error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s
    update!(status: 'error', error_message: message, completed_at: Time.current)
    bags.where.not(status: AptrustBag::TERMINAL).update_all(status: 'error', updated_at: Time.current)
  end

  def bag_counts
    bags.group(:status).count
  end

  def as_json(_options = {})
    {
      id: id,
      scope_type: scope_type,
      scope_id: scope_id,
      collection_id: collection_id,
      status: status,
      remote_state: remote_state,
      sid: sid,
      requested_by: requested_by,
      message: message,
      error_message: error_message,
      bag_counts: bag_counts,
      created_at: created_at,
      submitted_at: submitted_at,
      completed_at: completed_at,
      last_polled_at: last_polled_at
    }
  end

  private

  # The name of what was submitted, or its id
  def scope_label
    label = scope_type == 'media_object' ? MediaObject.find(scope_id).title : Admin::Collection.find(scope_id).name
    label.presence || scope_id
  rescue ActiveFedora::ObjectNotFoundError
    scope_id
  end
end
