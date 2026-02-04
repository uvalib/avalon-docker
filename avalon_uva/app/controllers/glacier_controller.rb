# frozen_string_literal: true

class GlacierController < ApplicationController
  before_action :set_master_file

  def request_masterfile
    authorize! :update, @master_file, message: 'You do not have sufficient privileges'

    gr = GlacierRequest.new(master_file: @master_file, email: current_user&.email)

    unless current_user && current_ability.is_administrator?
      gr.errors.add(:base, 'You do not have sufficient privileges')
      return render json: gr, status: :unauthorized
    end

    gr.send_request if gr.valid?

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
