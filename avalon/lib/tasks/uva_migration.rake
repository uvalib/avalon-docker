namespace :uva do
  namespace :migrate do

    require 'fileutils'

    desc "Migrate streaming assets from Wowza to Nginx formats"
    task :all_derivatives => :environment do

      derivative_count = Derivative.count

      puts "Checking and migrating #{derivative_count} Derivatives"

      Derivative.find_each({},{batch_size:5}) do |der|
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

    OLD_STREAM_DIR = '/rtmp_streams/' # base folder with files to migrate
    NEW_STREAM_DIR = ENV['ENCODE_WORK_DIR'] # usually "/streamfiles"
    def migrate_stream der
      if der.absolute_location.include? 'streamfiles'
        # Skip already migrated files
        puts "Skipping already migrated: #{der.id}"
        return
      end

      # Find the stream file using the original location
      old_location_split = der.absolute_location.split('/')
      old_file = OLD_STREAM_DIR + old_location_split[6..8].join('/')
      derivative_hash = old_location_split[6]

      # Set up file names
      old_file_name = old_location_split[8]
      file_name = old_file_name.split('.')[0]
      file_extension = old_file_name.split('.')[1]
      quality_level = der.quality

      new_dir = "#{NEW_STREAM_DIR}/#{derivative_hash}/outputs/"
      new_name = "#{file_name}-#{quality_level}.#{file_extension}"
      new_path =  new_dir + new_name

      # copy to the new file structure
      FileUtils.mkdir_p(new_dir)
      success = system('cp', old_file, new_path)
      if success && File.exists?(new_path)
        der.absolute_location = "file://" + new_path
        der.set_streaming_locations!
        der.save
        puts "Updated #{der.id}"

      else
        puts "File transfer failed for Derivative: #{der.id}"
      end
    end
  end
end