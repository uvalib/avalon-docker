# frozen_string_literal: true

namespace :uva do
  namespace :migrate do
    namespace :masterfiles do

      require 'fileutils'
      require 'rest-client'
      require 'json'

      desc 'Migrate validate and copy master files from lib_content* to avalon-archive-production'
      task from_lib_content: :environment do

        # *lib_content* locations
        q = 'q=has_model_ssim:"MasterFile"%20file_location_ssi:*lib_content*&q.op=AND&fl=id%20isPartOf_ssim%20file_location_ssi%20duration_ssi%20file_size_ltsi%20has_captions%3F_bs&wt=json&rows=10000'

        # 112 locations
        #q = 'q=has_model_ssim:"MasterFile"%20file_location_ssi:*lib_content112*&q.op=AND&fl=id%20isPartOf_ssim%20file_location_ssi%20duration_ssi%20file_size_ltsi%20has_captions%3F_bs&wt=json&rows=10000'

        # not matching *avalon-archive-production*
        #q = 'q=has_model_ssim:"MasterFile"%20-file_location_ssi:*avalon-archive-production*&q.op=AND&fl=id%20isPartOf_ssim%20file_location_ssi%20duration_ssi%20file_size_ltsi%20has_captions%3F_bs&wt=json&rows=10000'

        solr_query = ENV['SOLR_URL'] + '/select?' + q
        puts 'loading ' + solr_query
        mfSolrResp = RestClient.get(solr_query)
        mfSolr = JSON.parse(mfSolrResp.body)
        count = mfSolr['response']['numFound']
        puts "Found #{count} master files"
        @no_s3_source, @no_cardinal_source, @no_dest, @synced, @dest_only, @pending_restore, @not_checked, @copied, @restore_sent, @errors = [], [], [], [], [], [], [], [], [], []
        lib_content_not_checked = {}

        #setupSSH = `ssh -M naw4t@cardinal.lib.virginia.edu echo "connected"`
        #puts setupSSH
        mfSolr['response']['docs'].each do |mf|
          if mf['file_location_ssi'][%r{/lib_content60}] # 226 records lib_content60 became lib_content114
            #puts "renaming lib_content60 to lib_content114 for #{mf['file_location_ssi']}"
            mf['file_location_ssi'] = mf['file_location_ssi'].sub('lib_content60', 'lib_content114')
          end

          if mf['file_location_ssi'][%r{/lib_content105}] # 192 records, became lib_content112
            #puts "renaming lib_content105 to lib_content112 for #{mf['file_location_ssi']}"
            mf['file_location_ssi'] = mf['file_location_ssi'].sub('lib_content105', 'lib_content112')
          end

          if mf['file_location_ssi'][%r{/lib_content67}] # 1216 records, became lib_content112
            #puts "renaming lib_content67 to lib_content112 for #{mf['file_location_ssi']}"
            mf['file_location_ssi'] = mf['file_location_ssi'].sub('lib_content67', 'lib_content112')
          end

          if mf['file_location_ssi'][%r{/lib_content112}] # fix s3 path
            # actually in content112 bucket, same path
            mf['file_location_ssi'] = mf['file_location_ssi'].sub('/lib_content112/', 's3://content112/')
          end

          case old_path = mf['file_location_ssi']
          when %r{/lib_content114}, %r{/lib_content122}
            #puts old_path
            next
            source_byte_length = cardinal_check(old_path)

            unless source_byte_length
              @no_cardinal_source << mf
              next
            end
            verify_destination(mf, source_byte_length)

          when %r{s3://content112}
            source_object = FileLocator::S3File.new(old_path).object
            unless source_object.exists?
              @no_s3_source << mf
              next
            end
            dest_object = verify_destination(mf, source_object.content_length)
            unless dest_object.exists?
              if source_object.restore&.include?('ongoing-request="true"')
                @pending_restore << mf
              elsif source_object.restore&.include?('expiry-date')
                # Has been restored
                # Now copy to the destination
                @copied << mf if s3_copy(source_object, dest_object)
              elsif source_object.storage_class&.include?('GLACIER')
                @restore_sent << mf if send_s3_restore(source_object)
              else
                byebug
              end
            end

          when %r{/lib_content}
            lib_content_folder = old_path[/lib_content\d*/]
            lib_content_not_checked[lib_content_folder] = lib_content_not_checked[lib_content_folder].to_i + 1
          else
            @not_checked << mf
          end
        end

        puts "#{count} master files from solr"
        puts "No S3 source: #{@no_s3_source.count}"
        puts "No Cardinal source: #{@no_cardinal_source.count}"
        puts "No Dest: #{@no_dest.count}"
        puts "Synced: #{@synced.count}"
        #puts "Completed (destination only): #{@dest_only.count}"
        puts "Errors: #{@errors.count}"
        pp @errors

        puts "lib_content* Not Checked: #{lib_content_not_checked.count}"
        puts "Other Not Checked: #{@not_checked.count}"
        pp(@not_checked.map { |mf| mf['file_location_ssi'] })
        puts "Restore Pending: #{@pending_restore.count}"
        pp(@pending_restore.map { |mf| mf['file_location_ssi'] })

        puts "Copied: #{@copied.count}"
        pp(@copied.map { |mf| mf['file_location_ssi'] })

        puts "Restore Sent: #{@restore_sent.count}"
        pp(@restore_sent.map { |mf| mf['file_location_ssi'] })

        puts '--- No s3 source --- '
        @no_s3_source.each do |mf|
          #puts "#{mf['file_location_ssi']}|#{new_s3_path(mf['id'], mf['file_location_ssi'])}"
        end

        puts '--- no cardinal source ---'
        @no_cardinal_source.each do |mf|
          #puts "#{mf['file_location_ssi']}|#{new_s3_path(mf['id'], mf['file_location_ssi'])}"
        end

        puts 'Missing Destination:'
        @no_dest.each do |mf|
          #puts "#{mf['file_location_ssi']}|#{new_s3_path(mf['id'], mf['file_location_ssi'])}"
        end
        byebug
        puts 'Finished!'
      end

      def new_s3_path(id, old_path)
        s3_base_uri = 's3://avalon-archive-production/masterfiles' || Settings.master_file_management.path
        File.join(
          s3_base_uri,
          MasterFile.post_processing_move_filename(old_path, id:)
        )
      end

      def cardinal_check(old_path)
        out = `ssh -Sv naw4t@cardinal.lib.virginia.edu stat -c%s "#{old_path.shellescape}"`
        out.to_i.positive? && out.to_i
      end

      def verify_destination(mf, source_content_length)

        dest_name = new_s3_path(mf['id'], mf['file_location_ssi'])
        dest_object = FileLocator::S3File.new(dest_name).object

        #puts "Dest: #{dest_object.inspect}"
        if dest_object.exists?
          if source_content_length == dest_object.content_length
            #puts "#{mf['id']} Source and dest match"
            @synced << mf
          else
            @errors << "Mismatch content length: Source: #{mf['file_location_ssi']}: #{source_content_length}\nDest:#{dest_name}: #{dest_object.content_length}"
          end
        else
          @no_dest << mf
        end
        dest_object
      end

      def send_s3_restore s3_source
        puts "Sending Restore request for s3://#{s3_source.bucket_name}/#{s3_source.key}"
        begin
          s3_source.restore_object({
            restore_request: {
              days: 30,
              glacier_job_parameters: {
                tier: 'Standard' # required, accepts Standard, Bulk, Expedited
              },
            }
          })
        rescue Aws::S3::Errors::MalformedXML => e
          puts @errors << "Restore request failed: #{e.message}"
          return false
        rescue Aws::S3::Errors::RestoreAlreadyInProgress => e
          puts e
        end
        true
      end

      def s3_copy(s3_source, s3_dest)
        begin
          cp_resp = s3_source.copy_to(s3_dest, {multipart_copy: (s3_source.size > 5.megabytes )})
          if cp_resp.try(:key) == s3_dest.key
            return true
          else
            byebug
          end
        rescue Aws::S3::Errors::InvalidObjectState => e
          byebug
          @errors << "Copy failed: #{e.message}"
        end
        false
      end

      desc 'Migrate one MasterFile rake uva:migrate:one_master_file ID=xxxxxxx'
      task one_master_file: :environment do
        if ENV['ID'].blank?
          puts 'Include a MasterFile Id with this format: rake uva:migrate:one_master_file ID=xxxxxxx '
          return
        end
      end

    end
  end
end
