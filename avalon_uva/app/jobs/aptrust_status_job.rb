# frozen_string_literal: true

# Polls aptrust-submit for the state of submitted APTrust submissions and their bags
class AptrustStatusJob < ApplicationJob
  queue_as :aptrust

  def perform
    return unless Settings.aptrust&.enabled

    client = Aptrust::Client.new
    AptrustSubmission.where(status: 'submitted').where.not(sid: nil).find_each do |submission|
      poll(client, submission)
    rescue StandardError => e
      Rails.logger.error("[APTrust] status poll for #{submission.sid} failed: #{e.class}: #{e.message}")
    end
  end

  private

  def poll(client, submission)
    response = client.submission_status(submission.sid)
    return submission.update!(last_polled_at: Time.current) if response.nil?

    submission.bags.where.not(status: AptrustBag::TERMINAL).find_each do |bag|
      bag_response = client.bag_status(bag.bag_name)
      # bag status is the latest bag with that name, which may belong to a later submission
      next unless bag_response && bag_response['submission'] == submission.sid

      bag.update!(remote_state: bag_response['state'], status: AptrustBag.status_for_remote(bag_response['state']))
    end

    state = response['state']
    attrs = { remote_state: state, last_polled_at: Time.current }
    if AptrustSubmission::REMOTE_TERMINAL.include?(state)
      attrs.merge!(status: state, completed_at: Time.current)
      settle_bags(submission, state)
    end
    submission.update!(attrs)
  end

  def settle_bags(submission, state)
    remaining = submission.bags.where.not(status: AptrustBag::TERMINAL)
    case state
    when 'complete' then remaining.update_all(status: 'complete', updated_at: Time.current)
    when 'error', 'abandoned' then remaining.update_all(status: AptrustBag.status_for_remote(state), updated_at: Time.current)
    end
  end
end
