# frozen_string_literal: true

# Polls the aptrust-submit service for the state of APTrust submissions
Rails.application.config.to_prepare do
  next unless ActiveModel::Type::Boolean.new.cast(Settings.aptrust&.enabled)

  begin
    Sidekiq.redis(&:info)
    Sidekiq::Cron::Job.create(name: 'APTrust submission status - every 15min', cron: '*/15 * * * *', class: 'AptrustStatusJob')
  rescue Redis::CannotConnectError => e
    Rails.logger.warn "Cannot create APTrust sidekiq-cron job: #{e.message}"
  end
end
