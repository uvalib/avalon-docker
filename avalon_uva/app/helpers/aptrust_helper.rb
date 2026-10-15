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
end
