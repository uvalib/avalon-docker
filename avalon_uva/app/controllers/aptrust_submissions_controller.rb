# frozen_string_literal: true

# Self-serve APTrust submission of a collection from the collection management page
class AptrustSubmissionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_collection
  before_action :authorize_aptrust!

  def show
    respond_to do |format|
      format.html { render partial: 'aptrust_submissions/collection_status', locals: { collection: @collection } }
      format.json { render json: status_payload }
    end
  end

  def create
    submission = AptrustSubmission.with_collection_lock(@collection.id) do
      next nil if AptrustSubmission.in_progress_for_collection?(@collection.id)

      AptrustSubmission.create!(scope_type: 'collection', scope_id: @collection.id,
                                collection_id: @collection.id, requested_by: current_user.user_key)
    end
    AptrustSubmissionJob.perform_later(submission.id) if submission

    respond_to do |format|
      format.html do
        if submission
          flash[:success] = 'APTrust submission requested. Items that are new or changed since their last APTrust submission will be sent.'
        else
          flash[:error] = 'An APTrust submission is already in progress for this collection.'
        end
        redirect_to admin_collection_path(@collection)
      end
      format.json { render json: status_payload, status: submission ? :created : :conflict }
    end
  end

  private

  def set_collection
    @collection = Admin::Collection.find(params[:id])
  end

  def authorize_aptrust!
    return if helpers.can_submit_to_aptrust?(@collection)

    respond_to do |format|
      format.html do
        flash[:error] = 'You do not have sufficient privileges to submit this collection to APTrust.'
        redirect_to admin_collection_path(@collection)
      end
      format.json { render json: { errors: ['You do not have sufficient privileges'] }, status: :unauthorized }
    end
  end

  def status_payload
    {
      collection_id: @collection.id,
      in_progress: AptrustSubmission.in_progress_for_collection?(@collection.id),
      submissions: AptrustSubmission.for_collection(@collection.id).recent.limit(10).map(&:as_json)
    }
  end
end
