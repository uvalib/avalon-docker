# frozen_string_literal: true

require 'digest/md5'

module Aptrust
  # Stages one media object as a bag folder at s3://<bucket>/<deposit_path>/<bag_name>/ following the
  # aptrust-submit conventions: payload files plus a manifest-md5.txt at the folder root, with optional
  # aptrust-title.txt and aptrust-description.txt. The aptrust-submit bagger writes the BagIt tag files.
  # Derivatives are not included except as a logged fallback for a missing master file.
  class BagBuilder
    MANIFEST = 'manifest-md5.txt'
    TITLE = 'aptrust-title.txt'
    DESCRIPTION = 'aptrust-description.txt'
    RESERVED_NAMES = [MANIFEST, TITLE, DESCRIPTION, 'native-payload.json'].freeze
    MAX_SINGLE_COPY = 5 * 1024**3
    MAX_NAME_BYTES = 255

    attr_reader :manifest, :byte_size

    def initialize(bag:, bucket:, deposit_path:, s3_client: Aws::S3::Client.new)
      @bag = bag
      @bucket = bucket
      @prefix = "#{deposit_path}/#{bag.bag_name}"
      @s3 = s3_client
      @manifest = {}
      @byte_size = 0
    end

    def build!(media_object = MediaObject.find(@bag.media_object_id))
      put_data(TITLE, media_object.title.presence || media_object.id)
      put_data(DESCRIPTION, media_object.abstract.presence || media_object.title.presence || media_object.id)
      put_data('metadata/mods.xml', media_object.descMetadata.content)
      put_json('metadata/media_object.json', without_derivatives(media_object.as_json(include_structure: false)))
      put_json('metadata/collection.json', media_object.collection.as_json)
      add_supplemental_files('', media_object.supplemental_files)

      media_object.sections.each { |master_file| add_master_file(master_file) }

      write_manifest
      self
    end

    # Removes a partially staged bag so the bag folders under the submission match what is initiated
    def remove!
      @s3.list_objects_v2(bucket: @bucket, prefix: "#{@prefix}/").each do |page|
        objects = page.contents.map { |obj| { key: obj.key } }
        @s3.delete_objects(bucket: @bucket, delete: { objects: objects }) if objects.any?
      end
    end

    private

    def add_master_file(master_file)
      dir = "master_files/#{master_file.id}"
      source = SourceResolver.resolve(master_file)
      if source.fallback?
        Rails.logger.error("[APTrust] master file #{master_file.id} of media object #{@bag.media_object_id} not found at " \
                           "#{master_file.file_location.presence || master_file.masterFile}; staging derivative #{source.filename} instead")
      end

      put_source("#{dir}/#{source.filename}", source)
      put_json("#{dir}/master_file.json", master_file.to_ingest_api_hash(false).except(:files))
      put_data("#{dir}/structure.xml", master_file.structuralMetadata.content) if master_file.structuralMetadata.has_content?
      if master_file.captions.present? && master_file.captions.has_content?
        put_data("#{dir}/captions/#{master_file.captions.original_name.presence || 'captions'}", master_file.captions.content)
      end
      add_supplemental_files("#{dir}/", master_file.supplemental_files)
    end

    def add_supplemental_files(dir, supplemental_files)
      return if supplemental_files.blank?

      metadata = supplemental_files.map do |sf|
        path = put_data("#{dir}supplemental_files/#{sf.id}-#{sf.file.filename}", sf.file.download)
        supplemental_file_metadata(sf).merge(path: path)
      end
      put_json("#{dir}supplemental_files.json", metadata)
    end

    def supplemental_file_metadata(sf)
      display = begin
        sf.as_json
      rescue StandardError
        {}
      end
      display.merge(
        id: sf.id,
        label: sf.label,
        tags: sf.tags,
        language: sf.language,
        parent_id: sf.parent_id,
        filename: sf.file.filename.to_s,
        content_type: sf.file.content_type,
        created_at: sf.created_at,
        updated_at: sf.updated_at
      )
    end

    def without_derivatives(hash)
      hash.merge(files: Array(hash[:files]).map { |file| file.except(:files) })
    end

    def put_json(path, data)
      put_data(path, JSON.pretty_generate(data.as_json))
    end

    def put_data(path, content)
      path = unique_path(path)
      body = content.to_s
      digest = Digest::MD5.digest(body)
      @s3.put_object(bucket: @bucket, key: key_for(path), body: body, content_md5: Base64.strict_encode64(digest))
      record(path, digest.unpack1('H*'), body.bytesize)
    end

    def put_source(path, source)
      path = unique_path(path)
      key = key_for(path)
      if source.s3?
        source.s3_object.copy_to({ bucket: @bucket, key: key }, multipart_copy: source.size > MAX_SINGLE_COPY)
        # checksum the staged copy itself so the manifest reflects what aptrust-submit will bag
        digest = Digest::MD5.new
        @s3.get_object(bucket: @bucket, key: key) { |chunk| digest.update(chunk) }
        record(path, digest.hexdigest, source.size)
      else
        md5 = Digest::MD5.file(source.local_path).hexdigest
        Aws::S3::Object.new(bucket_name: @bucket, key: key, client: @s3).upload_file(source.local_path)
        record(path, md5, source.size)
      end
    end

    def write_manifest
      body = @manifest.sort.map { |path, md5| "#{md5} #{path}\n" }.join
      @s3.put_object(bucket: @bucket, key: key_for(MANIFEST), body: body,
                     content_md5: Base64.strict_encode64(Digest::MD5.digest(body)))
    end

    def record(path, md5, size)
      @manifest[path] = md5
      @byte_size += size.to_i
      path
    end

    def key_for(path)
      "#{@prefix}/#{path}"
    end

    # Sanitizes each path segment to the aptrust-submit validator rules and avoids collisions
    def unique_path(path)
      dirs = path.split('/')
      name = sanitize(dirs.pop)
      dirs = dirs.map { |d| sanitize(d) }
      # reserved names are only allowed as the title and description files at the bag folder root
      name = "file-#{name}" if RESERVED_NAMES.include?(name) && !(dirs.empty? && [TITLE, DESCRIPTION].include?(name))
      candidate = (dirs + [name]).join('/')
      counter = 1
      while @manifest.key?(candidate)
        ext = File.extname(name)
        candidate = (dirs + [truncate("#{File.basename(name, ext)}-#{counter}", ext)]).join('/')
        counter += 1
      end
      candidate
    end

    def sanitize(segment)
      clean = segment.to_s.unicode_normalize(:nfc)
                     .gsub(/[[:cntrl:] ]/, '_')
                     .gsub(/\\u00[0-9a-fA-F]{2}/, '_')
                     .sub(/\A-+/, '_')
      clean = 'file' if clean.blank? || clean == '.' || clean == '..'
      ext = File.extname(clean)
      truncate(File.basename(clean, ext), ext)
    end

    def truncate(base, ext)
      ext = '' if ext.bytesize > 32
      name = "#{base}#{ext}"
      return name if name.bytesize <= MAX_NAME_BYTES

      "#{base.byteslice(0, MAX_NAME_BYTES - ext.bytesize).scrub('')}#{ext}"
    end
  end
end
