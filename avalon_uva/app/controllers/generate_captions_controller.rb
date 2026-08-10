# frozen_string_literal: true

class GenerateCaptionsController < ApplicationController
  before_action :set_master_file

  def create
    authorize! :update, @master_file, message: 'You do not have sufficient privileges'

    request = GenerateCaptionsRequest.new(master_file: @master_file)

    unless current_user
      request.errors.add(:base, 'You do not have sufficient privileges')
      return render json: request, status: :unauthorized
    end

    request.process if request.valid?

    if request.errors.present?
      render json: request, status: :unprocessable_entity
    else
      render json: request, status: :created
    end
  end

  def set_master_file
    @master_file = MasterFile.find(params[:id])
  end
end
