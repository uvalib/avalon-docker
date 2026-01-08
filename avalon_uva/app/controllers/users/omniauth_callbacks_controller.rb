# Copyright 2011-2024, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # The default OmniAuth forms don't provide CSRF tokens, so we can't verify
  # them. Trying to verify results in a cleared session.
  skip_before_action :verify_authenticity_token

  def passthru
    # begin
    #   render "modules/#{params[:provider]}_auth_form"
    # rescue ActionView::MissingTemplate
    #   redirect_to new_user_session_path, flash: { alert: I18n.t('devise.failure.invalid') }

    provider = Avalon::Authentication::Providers.find { |p| p[:provider] == :shibboleth }
    callback = provider&.dig(:params, :callback_path)
    if callback
      redirect_to callback
    else
      Rails.logger.error 'Shibboleth requires a callback path.'
      raise 'Shibboleth error'
    end
  end

  def after_omniauth_failure_path_for(scope)
    case failed_strategy.name
    when 'lti'
      default_msg = I18n.t 'devise.omniauth_callbacks.failure', reason: failure_message
      msg = I18n.t 'devise.omniauth_callbacks.lti.failure', default: default_msg
      uri = Addressable::URI.parse request['launch_presentation_return_url']
      uri.query = {lti_errormsg: msg}.to_query
      uri.to_s
    else
      new_user_session_path(scope)
    end
  end

  def shibboleth
    shibboleth_callback_phase
    @user = User.find_or_create_by_username_or_email(@uid, @uid, 'shibboleth')
    if @user.persisted?
      flash[:success] = I18n.t 'devise.omniauth_callbacks.success', kind: :shibboleth
      sign_in @user, event: :authentication
      user_session[:virtual_groups] = @user.ldap_groups
      user_session[:full_login] = true
      user_session[:virtual_groups] += @affiliations
      Rails.logger.info "virtual_groups: #{@affiliations}"
    end

    if login_popup?
      flash[:success] = nil
      render inline: '<html><head><script>window.close();</script></head><body></body><html>'.html_safe
    else
      redirect_to find_redirect_url(:shibboleth, lti_group: user_session&.dig(:lti_group))
    end
  end

  def shibboleth_callback_phase
    eppn = request.env['HTTP_EPPN']
    affiliation = request.env['HTTP_AFFILIATION']
    if eppn.to_s.include?('@')
      @uid = eppn
    elsif affiliation
      parseAffiliationString(affiliation).each do |address|
        @uid = address if address.start_with?('member@')
      end
      @uid ||= 'unknown@unknown'
    else
      # this is an error... the apache module and rewrite haven't been properly setup.
      raise 'missing shibboleth header'
    end

    @affiliations = (parseAffiliationString(request.env['HTTP_AFFILIATION']) | getInferredAffiliations | parseMemberString(request.env['HTTP_MEMBER']))
  end

  def parseAffiliationString(affiliation)
    return [] unless affiliation.respond_to? :split
    affiliation.split(';')
  end

  def parseMemberString(members)
    return [] unless members.respond_to? :split
    members.split(';')
  end

  def getInferredAffiliations
    return [] unless @uid.respond_to? :gsub
    [@uid.gsub(/.+@/, 'member@')]
  end

  def action_missing(sym, *args, &block)
    logger.debug "Attempting to find user with #{sym.to_s} strategy"
    find_user(sym.to_s)
  end

  def login_popup?
    params['login_popup'].present? || (request.env["omniauth.params"].present? && request.env["omniauth.params"]["login_popup"].present?)
  end

  def find_user(auth_type)
    auth_type = auth_type.downcase
    find_method = "find_for_#{auth_type}".to_sym
    find_method = :find_for_generic unless User.respond_to?(find_method)
    logger.debug "#{auth_type} :: #{current_user.inspect}"
    @user = User.send(find_method,request.env["omniauth.auth"], current_user)
    if @user.persisted?
      flash[:success] = I18n.t "devise.omniauth_callbacks.success", :kind => auth_type
      sign_in @user, :event => :authentication
      user_session[:virtual_groups] = @user.ldap_groups
      user_session[:full_login] = true

      if auth_type == 'lti'
        user_session[:lti_group] = request.env["omniauth.auth"].extra.context_id
        user_session[:virtual_groups] += [user_session[:lti_group]]
        user_session[:full_login] = false
      end
    end

    if login_popup?
      flash[:success] = nil
      render inline: '<html><head><script>window.close();</script></head><body></body><html>'.html_safe
    else
      redirect_to find_redirect_url(auth_type, lti_group: user_session&.dig(:lti_group))
    end
  end

  protected :find_user

  rescue_from Avalon::MissingUserId do |exception|
    support_email = Settings.email.support
    notice_text = I18n.t('errors.lti_auth_error') % [support_email, support_email]
    redirect_to root_path, flash: { error: notice_text.html_safe }
  end

  rescue_from Avalon::DeletedUserId do |exception|
    support_email = Settings.email.support
    notice_text = I18n.t('errors.deleted_auth_error') % [support_email, support_email]
    redirect_to root_path, flash: { error: notice_text.html_safe }
  end

  rescue_from OAuth::Signature::UnknownSignatureMethod do |exception|
    notice_text = I18n.t('errors.general_auth_error')
    redirect_to root_path, flash: { error: notice_text }
  end
end
