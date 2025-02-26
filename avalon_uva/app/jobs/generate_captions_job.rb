require 'aws-sdk-transcribeservice'
class GenerateCaptionsJob < ActiveJob::Base
  queue_as :captions
  POLL_TIME = 1.minute


  def perform(master_file_id)
    master_file = MasterFile.find(master_file_id)
    return if master_file.nil?

    # Check for existing generated captions
    if master_file.supplemental_files(tag: ['caption', 'machine_generated']).present?
      Rails.logger.info "Captions already generated for #{master_file_id}"
      return
    end

    job_name = "#{master_file_id}-captions"

    # Check for existing transcription job
    client = Aws::TranscribeService::Client.new()
    begin
      resp = client.get_transcription_job({
        transcription_job_name: job_name, # required
      })
    rescue Aws::TranscribeService::Errors::BadRequestException => e
      # job not found
      Rails.logger.info "No existing transcription job for #{job_name}"
    end

    #Status is one of "QUEUED", "IN_PROGRESS", "FAILED", "COMPLETED"
    if resp.present?
      Rails.logger.info "Transcription job found\n#{resp.inspect}"
      case resp.transcription_job.transcription_job_status
      when 'COMPLETED'

        temp_uri = resp.transcription_job.subtitles.subtitle_file_uris.first
        raise "No caption file found" if temp_uri.blank?

        # Create the SupplementalFile
        main_language = resp.transcription_job.language_codes.sort_by(&:duration_in_seconds).last
        lang = Iso639[main_language.try(:language_code)]
        caption_file = SupplementalFile.new(
          label: main_language.language_code,
          tags: ['caption', 'machine_generated'],
          language: lang.nil? ? 'eng' : lang.alpha3_bibliographic,
        )
        begin
          caption_file.file.attach(io: URI.open(temp_uri),
            filename: "#{master_file_id}-generated-#{resp.transcription_job.language_code}.vtt",
            content_type: 'text/vtt'
          )
        rescue StandardError, LoadError => e
          raise Avalon::SaveError, "Error attaching caption file: #{e}"
        end

        # Checks adapted from app/controllers/supplemental_files_controller.rb
        # Raise errror if file wasn't attached
        raise Avalon::SaveError, "File could not be attached." unless caption_file.file.attached?
        raise Avalon::SaveError, caption_file.errors.full_messages unless caption_file.save

        # Add the caption file to the master file
        master_file.supplemental_files += [caption_file]
        raise Avalon::SaveError, master_file.errors[:supplemental_files_json].full_messages unless master_file.save

        # Successfully added the caption

        # Success, now cleanup
        media_uri = get_media_uri(master_file)
        tmp_location = Addressable::URI.parse("#{Settings.captions.tmp_s3}#{media_uri.path}")
        dest_object = FileLocator::S3File.new(tmp_location).object
        if dest_object.exists?
          Rails.logger.info("Deleting #{tmp_location}")
          dest_object.delete
        else
          Rails.logger.info("No file to clean up at #{tmp_location}")
        end
        Rails.logger.info("Done: #{job_name}")

        return

      when 'ERROR'
        # log
        Rails.logger.error(resp.transcription_job.failure_reason)
        return
      when "QUEUED", "IN_PROGRESS"
        # retry later
        Rails.logger.info("Transcription job still in progress")
        GenerateCaptionsJob.set(wait: POLL_TIME).perform_later(master_file_id)
        return
      end
    end

    # No existing job, start transcribing


    media_uri = get_media_uri(master_file)
    puts media_uri
    to_transcribe_uri = ""

    if media_uri.nil?
      raise 'No media file found'
    elsif media_uri.scheme == 'file'
      #copy_to_s3_transcribe_tmp()
      tmp_location = Addressable::URI.parse("#{Settings.captions.tmp_s3}#{media_uri.path}")
      dest_object = FileLocator::S3File.new(tmp_location).object
      if dest_object.exists?
        to_transcribe_uri = tmp_location
      else
        if dest_object.upload_file(media_uri.path)
          Rails.logger.info("Uploaded #{media_uri.path} to #{tmp_location}")
          to_transcribe_uri = tmp_location
        else
          raise "Could not upload #{media_uri.path} to #{tmp_location}"
        end
      end

    elsif media_uri.scheme == 's3'
      to_transcribe_uri = media_uri
    end
    Rails.logger.info to_transcribe_uri

    # https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/TranscribeService/Client.html#start_transcription_job-instance_method
    resp = client.start_transcription_job({
      transcription_job_name: job_name, # required,
      media: { # required
        media_file_uri: to_transcribe_uri.to_s,
      },
      settings: {
      },
      #identify_language: true,
      identify_multiple_languages: true,
      subtitles: {
        formats: ["vtt"], # accepts vtt, srt
        output_start_index: 0,
      },
    })
    Rails.logger.info "Transcription job submitted: #{resp.inspect}"
    GenerateCaptionsJob.set(wait: POLL_TIME).perform_later(master_file_id)
  end

  def get_media_uri master_file
    # Reusing uri selection from waveform_job.rb
    wfj = WaveformJob.new
    wfj.send(:derivative_file_uri, master_file) || wfj.send(:file_uri, master_file) || wfj.send(:playlist_url, master_file)

  end
end
