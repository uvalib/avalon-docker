# frozen_string_literal: true

require 'rails_helper'

describe AptrustHelper, type: :helper do
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
