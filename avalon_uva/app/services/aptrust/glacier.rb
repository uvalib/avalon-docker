# frozen_string_literal: true

module Aptrust
  # Glacier restore helpers for Aws::S3::Object, based on lib/tasks/s3_migration.rake
  module Glacier
    ARCHIVE_STORAGE_CLASSES = %w[GLACIER DEEP_ARCHIVE].freeze

    module_function

    # Readable now: not archived, or archived with a completed restore
    def available?(object)
      return true unless ARCHIVE_STORAGE_CLASSES.include?(object.storage_class.to_s)

      object.restore.to_s.include?('ongoing-request="false"')
    end

    def restore_pending?(object)
      object.restore.to_s.include?('ongoing-request="true"')
    end

    def request_restore(object)
      return if available?(object) || restore_pending?(object)

      Rails.logger.info("[APTrust] requesting restore of s3://#{object.bucket_name}/#{object.key}")
      object.restore_object(
        restore_request: {
          days: Settings.aptrust.restore_days,
          glacier_job_parameters: { tier: Settings.aptrust.restore_tier }
        }
      )
    rescue Aws::S3::Errors::RestoreAlreadyInProgress
      nil
    end
  end
end
