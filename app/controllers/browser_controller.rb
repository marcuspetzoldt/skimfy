class BrowserController < ApplicationController

  require 'skimfy'
  include SkimfyCore

  def browse

    session[:link] = params[:link]

    unless session[:link].blank?
      s = Skimfy.new(session[:link])
      @body = s.body
      @encoding = s.encoding
    end

  end

end
