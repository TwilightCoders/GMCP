# frozen_string_literal: true

require 'net/http'
require 'uri'

module GMCP
  module Gmail
    # RFC 8058 one-click unsubscribe.
    #
    # This is the one place GMCP talks to a host that is not Google, so the
    # rules are deliberately narrow:
    #
    #   * The target URL is read from the message's own List-Unsubscribe header.
    #     A caller cannot pass a URL in — otherwise this would be a general
    #     purpose "POST anywhere" tool wearing a Gmail costume.
    #   * https only. A mailto: entry is reported but never acted on, and a
    #     plaintext http:// entry is refused rather than downgraded silently.
    #   * One-click is only attempted when the sender advertises it via
    #     List-Unsubscribe-Post, which is what RFC 8058 requires. Without that
    #     header the link is a web page needing a human, not an endpoint.
    #
    # Note that unsubscribing confirms to the sender that the address is live.
    # That is fine for a legitimate business and a bad idea for a spammer; the
    # judgement of which is which is the caller's, not this module's.
    module Unsubscribe
      ONE_CLICK_BODY = 'List-Unsubscribe=One-Click'
      USER_AGENT     = 'GMCP'
      OPEN_TIMEOUT   = 10
      READ_TIMEOUT   = 20

      class NotSupported < StandardError; end
      class Failed       < StandardError; end

      # Returns { https:, mailto:, one_click:, raw: } — or nil if the message
      # carries no List-Unsubscribe header at all.
      def self.info(message_id)
        headers = Message.get_raw("messages/#{message_id}", format: 'metadata') do |parsed, _r|
          ((parsed[:data] || {})[:payload] || {})[:headers] || []
        end

        pick = lambda do |name|
          h = headers.find { |x| (x[:name] || x['name']).to_s.downcase == name }
          h && (h[:value] || h['value'])
        end

        raw = pick.call('list-unsubscribe')
        return nil if raw.nil? || raw.to_s.strip.empty?

        uris = raw.to_s.scan(/<([^>]+)>/).flatten
        uris = raw.to_s.split(',').map(&:strip) if uris.empty?

        {
          https:     uris.find { |u| u.start_with?('https://') },
          http:      uris.find { |u| u.start_with?('http://') },
          mailto:    uris.find { |u| u.start_with?('mailto:') },
          one_click: pick.call('list-unsubscribe-post').to_s.downcase.include?('one-click'),
          raw:       raw
        }
      end

      # Performs the unsubscribe. Returns the final HTTP status.
      def self.one_click!(message_id)
        details = info(message_id)
        raise NotSupported, 'message has no List-Unsubscribe header' if details.nil?
        unless details[:one_click]
          raise NotSupported,
                'sender does not advertise List-Unsubscribe-Post; the link needs a human'
        end
        if details[:https].nil?
          raise NotSupported,
                details[:http] ? 'only a plaintext http:// unsubscribe URL is offered; refusing to use it'
                               : 'no https unsubscribe URL offered (mailto only)'
        end

        post(details[:https])
      end

      def self.post(url, redirects_left: 3)
        uri = URI.parse(url)
        raise NotSupported, "refusing non-https unsubscribe URL: #{uri.scheme}" unless uri.is_a?(URI::HTTPS)

        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/x-www-form-urlencoded'
        req['User-Agent']   = USER_AGENT
        req.body            = ONE_CLICK_BODY

        resp = Net::HTTP.start(uri.host, uri.port,
                               use_ssl: true,
                               open_timeout: OPEN_TIMEOUT,
                               read_timeout: READ_TIMEOUT) { |h| h.request(req) }

        if resp.is_a?(Net::HTTPRedirection) && resp['location'] && redirects_left.positive?
          return post(URI.join(url, resp['location']).to_s, redirects_left: redirects_left - 1)
        end

        raise Failed, "unsubscribe endpoint returned HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)

        resp.code
      end
      private_class_method :post
    end
  end
end
