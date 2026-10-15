# frozen_string_literal: true

require 'rails_helper'

describe AptrustSubmissionsController, type: :controller do
  let(:collection) { FactoryBot.create(:collection, unit: Avalon::ControlledVocabulary.find_by_name(:units).first) }

  before { allow(Settings.aptrust).to receive(:enabled).and_return(true) }

  describe 'POST #create' do
    context 'as a collection manager' do
      before { login_user collection.managers.first }

      it 'requests a submission and starts the job' do
        expect(AptrustSubmissionJob).to receive(:perform_later)
        expect { post :create, params: { id: collection.id } }.to change(AptrustSubmission, :count).by(1)
        expect(response).to redirect_to(admin_collection_path(collection))
        expect(AptrustSubmission.last).to have_attributes(scope_type: 'collection', collection_id: collection.id, status: 'requested')
      end

      it 'refuses while a submission is in progress' do
        AptrustSubmission.create!(scope_type: 'collection', scope_id: collection.id, collection_id: collection.id, status: 'restoring')
        expect(AptrustSubmissionJob).not_to receive(:perform_later)
        expect { post :create, params: { id: collection.id }, format: :json }.not_to change(AptrustSubmission, :count)
        expect(response).to have_http_status(:conflict)
      end
    end

    context 'as an administrator' do
      before { login_as :administrator }

      it 'requests a submission' do
        allow(AptrustSubmissionJob).to receive(:perform_later)
        expect { post :create, params: { id: collection.id } }.to change(AptrustSubmission, :count).by(1)
      end
    end

    context 'as a collection editor' do
      before { login_user collection.editors.first }

      it 'is not allowed' do
        expect { post :create, params: { id: collection.id }, format: :json }.not_to change(AptrustSubmission, :count)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when APTrust is disabled' do
      before do
        allow(Settings.aptrust).to receive(:enabled).and_return(false)
        login_as :administrator
      end

      it 'is not allowed' do
        expect { post :create, params: { id: collection.id }, format: :json }.not_to change(AptrustSubmission, :count)
      end
    end
  end

  describe 'GET #show' do
    before { login_user collection.managers.first }

    it 'reports the collection status' do
      AptrustSubmission.create!(scope_type: 'collection', scope_id: collection.id, collection_id: collection.id, status: 'staging')
      get :show, params: { id: collection.id }, format: :json
      body = JSON.parse(response.body)
      expect(body['in_progress']).to be true
      expect(body['submissions'].first['status']).to eq 'staging'
    end
  end
end
