# frozen_string_literal: true

module AptrustHelper
  STATUS_LABELS = {
    'requested' => 'Requested',
    'restoring' => 'Restoring from Glacier',
    'staging' => 'Staging files',
    'submitted' => 'Submitted',
    'complete' => 'Complete',
    'incomplete' => 'Incomplete',
    'error' => 'Error',
    'abandoned' => 'Abandoned'
  }.freeze

  STATUS_STYLES = {
    'complete' => 'aptrust-state--complete',
    'incomplete' => 'aptrust-state--warning',
    'error' => 'aptrust-state--error',
    'abandoned' => 'aptrust-state--ended'
  }.freeze

  def aptrust_enabled?
    ActiveModel::Type::Boolean.new.cast(Settings.aptrust&.enabled) == true
  end

  # Collection managers and administrators may submit a collection to APTrust
  def can_submit_to_aptrust?(collection)
    return false unless aptrust_enabled? && current_user.present?
    return false if Settings.repository_read_only_mode

    current_ability.is_administrator? || current_user.in?(collection.managers)
  end

  def aptrust_status_label(submission)
    label = STATUS_LABELS.fetch(submission.status, submission.status.humanize)
    submission.status == 'submitted' && submission.remote_state.present? ? "#{label} (#{submission.remote_state})" : label
  end

  def aptrust_status_class(submission)
    STATUS_STYLES.fetch(submission.status, 'aptrust-state--active')
  end

  # Public "last archived to APTrust" line for a collection page, or nil when nothing has been archived
  def aptrust_archive_note(collection_id)
    note = AptrustBag.archive_note_for_collection(collection_id)
    tag.p(note, data: { testid: 'collection-aptrust-archive-note' }) if note
  end

  # Links the submission id to its page in the aptrust-submit client, when that page is configured
  def aptrust_submission_link(submission)
    return '—' if submission.sid.blank?

    base = Settings.aptrust&.submission_page_url
    return submission.sid if base.blank?

    link_to submission.sid, "#{base.chomp('/')}/#{ERB::Util.url_encode(submission.sid)}", target: '_blank', rel: 'noopener'
  end
end
