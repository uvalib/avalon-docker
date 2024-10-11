class GlacierRequest
  require 'rest-client'
  include ActiveModel::Model

  attr_accessor :email, :bucket, :bucket_key, :master_file
  validates :email, presence: true
  validate :check_bucket_location

  def send_request
    response = RestClient.post(ENV['GLACIER_REQUEST_URL'], request_payload)
    puts response.inspect
    # success

  rescue RestClient::Exception => e
    errors.add(:rest_client, e.inspect)
    errors.add(:response, response.inspect)
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