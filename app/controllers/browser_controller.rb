class BrowserController < ApplicationController

  require 'skimfy'
  include SkimfyCore

  def browse

    # Skimfy can not skimfy itself
    params[:link] = '' if params[:link].nil?
    session[:link] = params[:link].index(request.host) ? '' : params[:link]

    unless session[:link].blank?
      s = Skimfy.new(session[:link])
      @body = s.body
      @encoding = s.encoding
      @baseurl = s.baseurl
      @title = s.title
      @site = shorten(s.baseurl)
    end

  end

  private

  def shorten(url)
    s = url.index('//')
    s = s.nil? ? 0 : s + 2
    short = url[s..-1]
    e = short.index('/') || 0
    short[0..(e - 1)]
  end

end
