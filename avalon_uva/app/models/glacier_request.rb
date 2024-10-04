class GlacierRequest
  require 'rest-client'
  include ActiveModel::Model

  attr_accessor :email, :bucket, :bucket_key, :master_file
  validates :email, presence: true
  validate :check_bucket_location

  def send_request
    response = RestClient.post(ENV['GLACIER_REQUEST_URL'], { email: email, bucket: bucket, bucket_key: bucket_key })

    if response.code == 200
    else
      errors.add(:glacier_response, response.inspect)
    end
  end

  protected
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