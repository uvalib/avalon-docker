class GlacierRequest
  require 'rest-client'
  include ActiveModel::Model

  attr_accessor :email, :bucket, :bucket_key, :master_file, :message
  validates :email, presence: true
  validate :check_bucket_location

  def send_request
    begin
      response = RestClient.post(ENV['GLACIER_REQUEST_URL'], request_payload.to_json)
      self.message = "Master file requested. You will receive an email when it is ready."

    rescue RestClient::Exception => e
      self.message = "Master file could not be requested."
      errors.add(:rest_client, e.inspect)
      errors.add(:response, e.response.body)
    rescue StandardError => e
      self.message = "Master file could not be requested."
      errors.add(e.class.to_s, e.inspect)
    end
  end

  private

  def request_payload
    {
      bucket: bucket,
      key: bucket_key,
      email: email
    }
  end

  def check_bucket_location
    uri = URI.parse(master_file.masterFile)
    self.bucket = uri.host.split('.')[0]
    self.bucket_key = uri.path[1..-1] # Remove leading slash

    if bucket.blank?
      errors.add(:bucket, "not found")
    elsif bucket_key.blank?
      errors.add(:bucket_key, "not found")
    end
    errors.blank?
  end
end