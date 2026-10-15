# frozen_string_literal: true

require 'rails_helper'

describe Aptrust::SourceResolver do
  let(:local_file) { Tempfile.new(['master', '.mov']).tap { |f| f.write('bytes'); f.flush } }
  let(:derivatives) { [] }
  let(:master_file) do
    double(id: 'mf1', file_location: location, masterFile: location, original_filename: 'original.mov', derivatives: derivatives)
  end

  context 'with a local master file' do
    let(:location) { local_file.path }

    it 'uses the master file with its original filename' do
      source = described_class.resolve(master_file)
      expect(source.local_path).to eq local_file.path
      expect(source.filename).to eq 'original.mov'
      expect(source).not_to be_fallback
    end
  end

  context 'with a master file in S3' do
    let(:location) { 's3://archive/masterfiles/mf1-original.mov' }

    it 'uses the S3 object' do
      Aws.config[:s3] = { stub_responses: { head_object: { content_length: 42 } } }
      source = described_class.resolve(master_file)
      expect(source).to be_s3
      expect(source.s3_object.bucket_name).to eq 'archive'
      expect(source.size).to eq 42
    ensure
      Aws.config.delete(:s3)
    end
  end

  context 'with a missing master file' do
    let(:location) { '/nowhere/missing.mov' }
    let(:derivatives) do
      [double(quality: 'low', download_path: '/nowhere/low.mp4'), double(quality: 'high', download_path: local_file.path)]
    end

    it 'falls back to the highest quality derivative' do
      source = described_class.resolve(master_file)
      expect(source).to be_fallback
      expect(source.local_path).to eq local_file.path
      expect(source.filename).to start_with 'derivative-high-'
    end
  end

  context 'with a master file on an external server and no derivative' do
    let(:location) { 'https://media.example.com/master.mov' }

    it 'raises' do
      expect { described_class.resolve(master_file) }.to raise_error(Aptrust::Error)
    end
  end
end
