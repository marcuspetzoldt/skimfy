class BrowserController < ApplicationController

  require 'skimfy'
  include SkimfyCore

  def browse

    session[:link] = params[:link]

    if session[:link]
      s = Skimfy.new(session[:link])
      @page = s.page
    end

  end

end
