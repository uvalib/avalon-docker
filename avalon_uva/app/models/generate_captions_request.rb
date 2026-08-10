# frozen_string_literal: true

class GenerateCaptionsRequest
  include ActiveModel::Model

  attr_accessor :master_file, :message

  validate :captions_do_not_exist
  validate :job_not_in_progress

  def process
    GenerateCaptionsJob.perform_later(master_file.id)
    self.message = 'Caption generation started.'
  rescue StandardError => e
    self.message = 'Caption generation could not be started.'
    errors.add(e.class.to_s, e.inspect)
  end

  def as_json(_options = {})
    {
      message: message,
      errors: errors.to_hash
    }
  end

  private

  def captions_do_not_exist
    return if master_file.blank?
    return if master_file.supplemental_files(tag: %w[caption machine_generated]).blank?

    self.message = 'Generated captions already exist. Reload the page.'
    errors.add(:base, 'Generated captions already exist. Reload the page.')
  end

  def job_not_in_progress
    return if master_file.blank?
    return unless GenerateCaptionsJob.in_progress?(master_file.id)

    self.message = 'Caption generation is already in progress.'
    errors.add(:base, 'Caption generation is already in progress')
  end
end
