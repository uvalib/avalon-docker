class GlacierRequest
  require 'rest-client'
  include ActiveModel::Model

  attr_accessor :email, :bucket, :bucket_key, :master_file
  validates :email, presence: true
  validate :check_bucket_location

  def send_request
    response = RestClient.post(ENV['GLACIER_REQUEST_URL'], request_payload)

    # success

  rescue RestClient::Exception => e
    errors.add(:glacier_response, error.inspect)
  end

  private

  def request_payload
    {
      email: email,
      bucket: bucket,
      bucket_key: bucket_key
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