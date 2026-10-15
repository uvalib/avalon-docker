# frozen_string_literal: true

require 'rails_helper'

describe Aptrust::BagBuilder do
  let(:s3) { Aws::S3::Client.new(stub_responses: true) }
  let(:bag) { AptrustBag.new(media_object_id: 'mo1', bag_name: 'Avalon-mo1') }
  let(:builder) { described_class.new(bag: bag, bucket: 'inbound', deposit_path: 'cid/sid', s3_client: s3) }
  let(:master_file_path) do
    Tempfile.new(['master', '.mp4']).tap { |f| f.write('master file bytes'); f.flush }.path
  end
  let(:caption) do
    double(id: 7, label: 'English captions', tags: ['caption'], language: 'eng', parent_id: 'mf1',
           created_at: Time.current, updated_at: Time.current, as_json: { type: 'caption' },
           file: double(filename: 'captions.vtt', content_type: 'text/vtt', download: "WEBVTT\n"))
  end
  let(:master_file) do
    double(id: 'mf1', file_location: master_file_path, masterFile: master_file_path, original_filename: '-bad name.mp4',
           to_ingest_api_hash: { id: 'mf1', files: [{ id: 'derivative' }] },
           structuralMetadata: double(has_content?: true, content: '<Item/>'),
           captions: nil, supplemental_files: [caption])
  end
  let(:media_object) do
    double(id: 'mo1', title: 'A title', abstract: nil, descMetadata: double(content: '<mods/>'),
           as_json: { id: 'mo1', files: [{ id: 'mf1', files: [{ id: 'derivative' }] }] },
           collection: double(as_json: { id: 'col1' }), supplemental_files: [], sections: [master_file])
  end

  def put_requests
    s3.api_requests.select { |r| r[:operation_name] == :put_object }.to_h { |r| [r[:params][:key], r[:params][:body]] }
  end

  before { builder.build!(media_object) }

  it 'stages the bag folder under the submission path with a manifest' do
    keys = put_requests.keys
    expect(keys).to all(start_with('cid/sid/Avalon-mo1/'))
    expect(keys).to include('cid/sid/Avalon-mo1/manifest-md5.txt', 'cid/sid/Avalon-mo1/aptrust-title.txt',
                            'cid/sid/Avalon-mo1/aptrust-description.txt', 'cid/sid/Avalon-mo1/metadata/mods.xml',
                            'cid/sid/Avalon-mo1/metadata/collection.json',
                            'cid/sid/Avalon-mo1/master_files/mf1/structure.xml',
                            'cid/sid/Avalon-mo1/master_files/mf1/supplemental_files/7-captions.vtt',
                            'cid/sid/Avalon-mo1/master_files/mf1/supplemental_files.json')
  end

  it 'lists every staged file with its md5 in the manifest' do
    manifest = put_requests['cid/sid/Avalon-mo1/manifest-md5.txt'].lines.to_h { |l| l.chomp.split(' ', 2).reverse }
    expect(manifest.keys).to match_array(builder.manifest.keys)
    expect(manifest['aptrust-title.txt']).to eq Digest::MD5.hexdigest('A title')
    expect(manifest['master_files/mf1/_bad name.mp4']).to eq Digest::MD5.hexdigest('master file bytes')
  end

  it 'excludes derivatives from metadata' do
    media_object_json = JSON.parse(put_requests['cid/sid/Avalon-mo1/metadata/media_object.json'])
    expect(media_object_json['files'].first).not_to have_key('files')
    master_file_json = JSON.parse(put_requests['cid/sid/Avalon-mo1/master_files/mf1/master_file.json'])
    expect(master_file_json).not_to have_key('files')
  end

  it 'records supplemental file metadata' do
    metadata = JSON.parse(put_requests['cid/sid/Avalon-mo1/master_files/mf1/supplemental_files.json'])
    expect(metadata.first).to include('id' => 7, 'tags' => ['caption'], 'language' => 'eng', 'parent_id' => 'mf1',
                                      'path' => 'master_files/mf1/supplemental_files/7-captions.vtt')
  end

  describe 'file names' do
    subject(:path) { builder.send(:unique_path, name) }

    context 'with a reserved name below the bag root' do
      let(:name) { 'supplemental_files/manifest-md5.txt' }
      it { is_expected.to eq 'supplemental_files/file-manifest-md5.txt' }
    end

    context 'with control characters' do
      let(:name) { "a\tb c.txt" }
      it { is_expected.to eq 'a_b_c.txt' }
    end

    context 'with a name over 255 bytes' do
      let(:name) { "#{'x' * 300}.wav" }
      it { expect(path.bytesize).to eq 255 }
      it { is_expected.to end_with '.wav' }
    end

    context 'with a name already staged' do
      let(:name) { 'aptrust-title.txt' }
      it { is_expected.to eq 'aptrust-title-1.txt' }
    end
  end
end
