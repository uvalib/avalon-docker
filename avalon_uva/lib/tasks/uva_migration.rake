namespace :uva do
  namespace :migrate do

    require 'fileutils'

    desc "Migrate streaming assets from Wowza to Nginx formats"
    task :all_derivatives => :environment do

      derivative_count = Derivative.count

      puts "Checking and migrating #{derivative_count} Derivatives"

      Derivative.find_each({},{batch_size: 10}) do |der|
        migrate_stream(der)
      end
      puts "Finished!"
    end

    desc "Migrate one Derivative rake uva:migrate:one_derivative ID=xxxxxxx"
    task :one_derivative => :environment do
      if ENV['ID'].blank?
        puts "Include a Derivative Id with this format: rake uva:migrate:one_derivative ID=xxxxxxx "
        return
      end
      der = Derivative.find(ENV['ID'])
      migrate_stream(der)

    end

    OLD_STREAM_DIR = '/streamfiles' # base folder with files to migrate
    NEW_STREAM_DIR = Settings.encoding.derivative_bucket
    def migrate_stream der
      if der.absolute_location.begin_with?('s3://')
        # Skip already migrated files
        puts "Skipping already migrated: #{der.id}"
        return
      end

      # Find the stream file using the original location
      old_location_split = der.absolute_location.split('/')
      derivative_uuid = old_location_split[4]
      quality_level = der.quality

      # original filenames were "VHS_14548_1-high.mp4"
      # need to be VHS_14548_1.mp4
      new_filename = old_location_split.last.gsub("-#{quality_level}.", '.')

      # match the elastic transcoder output
      new_path = "s3://#{NEW_STREAM_DIR}/#{derivative_hash}/quality-#{quality_level}/#{new_filename}"

      success = false
      if FileLocator.exists?(new_path)
        # already exists but derivative locations still needs updating
        puts "Derivative already copied."
        success = true
      elsif !FileLocator.exists?(der.absolute_location)
        puts "Derivative file does not exist at: #{der.absolute_location}"
      else
        # copy to s3
        dest_object = FileLocator::S3File.new(new_path).object
        original_uri = Addressable::URI.parse(der.absolute_location)

        if dest_object.upload_file(original_uri.path)
          success = true
        end

      end

      if success
        der.absolute_location = new_path
        der.set_streaming_locations!
        der.save
        puts "Location updated for derivative #{der.id} - #{derivative_uuid}"

      else
        puts "S3 transfer failed for Derivative: #{der.id} - #{derivative_uuid}"
      end
    end
  end
end