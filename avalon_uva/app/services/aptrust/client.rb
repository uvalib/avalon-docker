# frozen_string_literal: true

require 'rest-client'

module Aptrust
  # HTTP client for the uvalib aptrust-submit service (see uvalib/aptrust-submit-lambda)
  class Client
    def initialize(settings = Settings.aptrust)
      @settings = settings
    end

    # => { 'sid' => ..., 'bucket' => ..., 'path' => '<cid>/<sid>' }
    def register(collection:)
      post(@settings.register_url, cid: @settings.client_id, collection: collection)
    end

    # bag_folders must exactly match the bag folders staged under <path>/
    # => { 'submission' => ..., 'status' => 'validating', 'updated' => ... }
    def initiate(sid:, bag_folders:)
      post(@settings.submit_url, cid: @settings.client_id, sid: sid, bag_folders: bag_folders)
    end

    # => { 'submission' => ..., 'state' => ..., 'updated' => ... } or nil when unknown
    def submission_status(sid)
      get(@settings.submission_status_url, sid: sid)
    end

    # Latest bag with this name across all submissions
    # => { 'submission' => ..., 'name' => ..., 'state' => ..., 'updated' => ... } or nil when unknown
    def bag_status(bag_name)
      get(@settings.bag_status_url, bid: bag_name)
    end

    private

    def post(url, payload)
      require_configured!(url)
      response = RestClient::Request.execute(method: :post, url: url, payload: payload.to_json, timeout: timeout,
                                             headers: { content_type: :json, accept: :json })
      JSON.parse(response.body)
    rescue RestClient::ExceptionWithResponse => e
      raise Aptrust::Error, "POST #{url} failed (#{e.http_code}): #{e.response&.body}"
    end

    def get(url, params)
      require_configured!(url)
      response = RestClient::Request.execute(method: :get, url: url, timeout: timeout,
                                             headers: { accept: :json, params: params })
      JSON.parse(response.body)
    rescue RestClient::NotFound
      nil
    rescue RestClient::ExceptionWithResponse => e
      raise Aptrust::Error, "GET #{url} failed (#{e.http_code}): #{e.response&.body}"
    end

    def require_configured!(url)
      missing = []
      missing << 'client_id' if @settings.client_id.blank?
      missing << 'service URL' if url.blank?
      return if missing.empty?

      raise Aptrust::Error, "APTrust is not configured (missing #{missing.join(' and ')}); see the aptrust settings"
    end

    def timeout
      @settings.http_timeout || 60
    end
  end
end
