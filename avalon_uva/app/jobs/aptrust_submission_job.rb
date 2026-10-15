# frozen_string_literal: true

# Drives an AptrustSubmission through planning, Glacier restore, staging and initiation.
# Each run does one step and re-enqueues itself, so long collections checkpoint per bag and
# survive worker restarts. Status after initiation is tracked by AptrustStatusJob.
class AptrustSubmissionJob < ApplicationJob
  queue_as :aptrust

  def perform(submission_id)
    submission = AptrustSubmission.find_by(id: submission_id)
    return if submission.nil? || submission.terminal? || submission.status == 'submitted'

    case submission.status
    when 'requested'
      return if submission.bags.empty? && !plan(submission)

      restore(submission)
    when 'restoring'
      restore(submission)
    when 'staging'
      stage(submission)
    end
  rescue StandardError => e
    Rails.logger.error("[APTrust] submission #{submission_id} failed: #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
    submission&.fail!(e)
  end

  private

  # Selects the collection's published media objects that need preserving and splits them into chunks,
  # one aptrust-submit submission per chunk. Returns false when there is nothing to send.
  def plan(submission)
    collection = Admin::Collection.find(submission.scope_id)
    ids = collection.media_object_ids.select do |id|
      media_object = MediaObject.find(id)
      media_object.published? && media_object.sections.any? && AptrustBag.needs_submission?(media_object)
    end

    if ids.empty?
      submission.update!(status: 'complete', completed_at: Time.current,
                         message: 'No new or changed published items to submit')
      return false
    end

    chunks = ids.each_slice(Settings.aptrust.max_bags_per_submission.to_i.clamp(1, 1000)).to_a
    add_bags(submission, chunks.shift)
    chunks.each do |chunk|
      extra = AptrustSubmission.create!(submission.slice(:scope_type, :scope_id, :collection_id, :requested_by))
      add_bags(extra, chunk)
      self.class.perform_later(extra.id)
    end
    submission.update!(message: "#{ids.size} item(s) selected in #{chunks.size + 1} submission(s)") if chunks.any?
    true
  end

  def add_bags(submission, media_object_ids)
    media_object_ids.each do |id|
      submission.bags.create!(media_object_id: id, bag_name: AptrustSubmission.bag_name_for(id))
    end
  end

  # Requests restores for archived master files and waits until all are readable
  def restore(submission)
    pending = 0
    submission.bags.where(status: 'pending').find_each do |bag|
      MediaObject.find(bag.media_object_id).sections.each do |master_file|
        source = Aptrust::SourceResolver.resolve(master_file)
        next if !source.s3? || Aptrust::Glacier.available?(source.s3_object)

        Aptrust::Glacier.request_restore(source.s3_object)
        pending += 1
      end
    rescue StandardError => e
      fail_bag(bag, e)
    end

    if pending.positive?
      submission.update!(status: 'restoring', message: "Waiting on #{pending} file(s) to restore from Glacier")
      self.class.set(wait: Settings.aptrust.restore_poll.to_i.seconds).perform_later(submission.id)
    else
      submission.update!(status: 'staging', message: nil)
      self.class.perform_later(submission.id)
    end
  end

  # Stages one bag per run; initiates the submission once no bags remain to stage
  def stage(submission)
    bag = submission.bags.where(status: %w[pending staging]).order(:id).first
    return initiate(submission) if bag.nil?

    register(submission) if submission.sid.blank?

    builder = Aptrust::BagBuilder.new(bag: bag, bucket: submission.bucket, deposit_path: submission.deposit_path)
    begin
      bag.update!(status: 'staging')
      media_object = MediaObject.find(bag.media_object_id)
      modified_at = AptrustBag.source_modified_at(media_object)
      builder.build!(media_object)
      bag.update!(status: 'staged', source_modified_at: modified_at,
                  file_count: builder.manifest.size, byte_size: builder.byte_size)
    rescue StandardError => e
      fail_bag(bag, e)
      builder.remove!
    end
    self.class.perform_later(submission.id)
  end

  def register(submission)
    response = Aptrust::Client.new.register(collection: submission.collection_name)
    submission.update!(sid: response['sid'], bucket: response['bucket'], deposit_path: response['path'])
  end

  def initiate(submission)
    staged = submission.bags.where(status: 'staged')
    return submission.fail!('No items could be staged') if staged.none?

    response = Aptrust::Client.new.initiate(sid: submission.sid, bag_folders: staged.pluck(:bag_name))
    staged.update_all(status: 'submitted', updated_at: Time.current)
    submission.update!(status: 'submitted', remote_state: response['status'], submitted_at: Time.current, message: nil)
  end

  def fail_bag(bag, error)
    Rails.logger.error("[APTrust] bag #{bag.bag_name} failed: #{error.class}: #{error.message}")
    bag.update!(status: 'error', error_message: "#{error.class}: #{error.message}")
  end
end
