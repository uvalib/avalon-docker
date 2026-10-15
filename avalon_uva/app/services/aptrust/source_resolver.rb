# frozen_string_literal: true

module Aptrust
  # Finds the preservation source for a master file: the master file itself in S3 or on local disk,
  # or, when the master file cannot be found or lives on an external server, its highest quality derivative.
  class SourceResolver
    Source = Struct.new(:s3_object, :local_path, :size, :filename, :fallback, keyword_init: true) do
      def s3?
        s3_object.present?
      end

      def fallback?
        fallback == true
      end
    end

    DERIVATIVE_PREFERENCE = %w[high medium low].freeze

    def self.resolve(master_file)
      new(master_file).resolve
    end

    def initialize(master_file)
      @master_file = master_file
    end

    def resolve
      location = @master_file.file_location.presence || @master_file.masterFile
      source = locate(location)
      return source.tap { |s| s.filename = @master_file.original_filename.presence || s.filename } if source

      derivative = @master_file.derivatives.min_by { |d| DERIVATIVE_PREFERENCE.index(d.quality) || DERIVATIVE_PREFERENCE.size }
      source = derivative && locate(derivative.download_path)
      raise Aptrust::Error, "No master file or derivative found for master file #{@master_file.id} (#{location})" if source.nil?

      source.fallback = true
      source.filename = "derivative-#{derivative.quality}-#{source.filename}"
      source
    end

    private

    def locate(location)
      return nil if location.blank?

      uri = FileLocator.new(location).uri
      case uri.scheme
      when 's3'
        s3_source(FileLocator::S3File.new(uri.to_s).object)
      when 'file'
        path = Addressable::URI.unencode(uri.path)
        Source.new(local_path: path, size: File.size(path), filename: File.basename(path)) if File.file?(path)
      when 'http', 'https'
        # virtual-hosted S3 URLs (bucket.s3.region.amazonaws.com/key); anything else is an external server
        match = uri.host.to_s.match(/\A(?<bucket>.+)\.s3[.-]([a-z0-9-]+\.)?amazonaws\.com\z/)
        match && s3_source(Aws::S3::Object.new(bucket_name: match[:bucket], key: Addressable::URI.unencode(uri.path).sub(%r{\A/}, '')))
      end
    end

    def s3_source(object)
      return nil unless object.exists?

      Source.new(s3_object: object, size: object.content_length, filename: File.basename(object.key))
    end
  end
end
