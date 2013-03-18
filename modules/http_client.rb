# 
# Copyright (C) 2010-2012 Kyle Johnson <kyle@vacantminded.com>, Alex Iadicicco
# (http://terminus-bot.net/)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# 

require 'uri'
require 'em-http-request'

module Bot

  MODULE_LOADED_HTTP  = true
  MODULE_VERSION_HTTP = 0.2

  class Command

    def http_get uri, query = {}, silent_err = false, &block
      Bot.http_request uri, query, true, @msg, silent_err, &block
    end

    def http_post uri, query = {}, silent_err = false, &block
      Bot.http_request uri, query, false, @msg, silent_err, &block
    end

  end

  def self.http_get uri, query = {}, msg = nil, silent_err = false, &block
    Bot.http_request uri, query, true, msg, silent_err, &block
  end

  def self.http_post uri, query = {}, msg = nil, silent_err = false, &block
    Bot.http_request uri, query, false, msg, silent_err, &block
  end

  # Should not be called directly.
  def self.http_request uri, query, get, msg, silent_err, &block
    $log.debug("Bot.http_request") { uri }

    conf = Conf[:modules][:http_client]

    ua = conf[:user_agent] or "Terminus-Bot (http://terminus-bot.net/)"

    # TODO: Let callers add headers.

    conn_opts = {
      :connect_timeout    => (conf[:timeout] or 5),
      :inactivity_timeout => (conf[:timeout] or 5)
    }

    if conf[:proxy_address]
      proxy = {
        :host => conf[:proxy_address],
        :port => (conf[:proxy_port] or 8080)
      }

      if conf[:proxy_username] and conf[:proxy_password]
        proxy[:authentication] = [
          conf[:proxy_username],
          conf[:proxy_password]
        ]
      end

      if conf[:proxy_type]
        proxy[:type] = conf[:proxy_type].to_sym
      end
    
      conn_opts[:proxy] = proxy
    end

    http = EventMachine::HttpRequest.new uri, conn_opts
    
    args = {
      :query              => query,
      :head               => { 'User-agent' => ua },
      :redirects          => (conf[:redirects] or 10)
    }

    max_time = conf[:max_time].to_i rescue 5

    EM.add_timer(max_time) do
      http.conn.close_connection
    end

    if get
      req = http.get  args
    else
      req = http.post args
    end

    req.callback do
      req.response.fix_encoding!

      begin
        block.call(req)
      rescue => e
        $log.error('Bot.http_request') { "#{uri} callback error: #{e}" }

        unless msg.nil? or silent_err
          msg.connection.send_reply msg, "Error: #{e}"
        end

      end
    end

    req.errback do
      $log.error('Bot.http_request') { "#{uri} errback for: #{req.error}" }

      req.response.fix_encoding!

      begin
        block.call(req)
      rescue => e
        $log.error('Bot.http_request') { "#{uri} errback error: #{e}" }

        unless msg.nil? or silent_err
          msg.connection.send_reply msg, "Error: #{e}"
        end

      end
    end
  end
end
