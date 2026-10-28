# frozen_string_literal: true

require 'rails_helper'

describe AptrustHelper, type: :helper do
  describe '#aptrust_archive_note' do
    it 'renders the collection archive sentence' do
      allow(AptrustBag).to receive(:archive_note_for_collection).with('col1').and_return('This collection was last archived to APTrust on October 28, 2026.')
      note = Nokogiri::HTML.fragment(helper.aptrust_archive_note('col1')).at('p')
      expect(note.text).to eq 'This collection was last archived to APTrust on October 28, 2026.'
      expect(note['data-testid']).to eq 'collection-aptrust-archive-note'
    end

    it 'renders nothing when the collection has never been archived' do
      allow(AptrustBag).to receive(:archive_note_for_collection).with('col1').and_return(nil)
      expect(helper.aptrust_archive_note('col1')).to be_nil
    end
  end

  describe '#aptrust_submission_link' do
    let(:submission) { AptrustSubmission.new(sid: 'sid-abc123') }

    it 'links the sid to its aptrust-submit page' do
      allow(Settings.aptrust).to receive(:submission_page_url).and_return('https://aptrust-submit-dev.lib.virginia.edu/submissions/')
      link = Nokogiri::HTML.fragment(helper.aptrust_submission_link(submission)).at('a')
      expect(link['href']).to eq 'https://aptrust-submit-dev.lib.virginia.edu/submissions/sid-abc123'
      expect(link.text).to eq 'sid-abc123'
      expect(link['target']).to eq '_blank'
    end

    it 'shows the plain sid when no page is configured' do
      allow(Settings.aptrust).to receive(:submission_page_url).and_return(nil)
      expect(helper.aptrust_submission_link(submission)).to eq 'sid-abc123'
    end

    it 'shows a dash before the submission is registered' do
      expect(helper.aptrust_submission_link(AptrustSubmission.new)).to eq '—'
    end
  end
end
