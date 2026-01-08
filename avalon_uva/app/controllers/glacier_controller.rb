# frozen_string_literal: true

class GlacierController < ApplicationController
  before_action :set_master_file

  def request_masterfile

    authorize! :update, @master_file, message: 'You do not have sufficient privileges'

    if current_user && current_ability.is_administrator?
      gr = GlacierRequest.new(master_file: @master_file, email: current_user.email)
      gr.send_request if gr.valid?
    else
      render json: gr, status: :unauthorized
      return
    end

    return render json: gr, status: :created
    if gr.errors.present?
      render json: gr, status: :unprocessable_entity
    else
      render json: gr, status: :created
    end
  end

  def set_master_file
    @master_file = MasterFile.find(params[:id])
  end
end
