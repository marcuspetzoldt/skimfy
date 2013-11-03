module SkimfyCore

  require 'nokogiri'
  require 'open-uri'
  require 'openssl'
  require 'net/http'

  class Skimfy

    def page=(b)
      @page = b
    end

    def page
      @page.xpath('//body').children
    end

    def initialize(filename)

      return if filename.blank?

      rescues = 0
      @baseurl = filename.last == '/' ? filename[0..-2] : filename

      begin
        @page = Nokogiri::HTML(open(filename, ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE))
        skim
        reformat
      rescue Exception => e
        case rescues
          when 0
            # Try to reload the page with explicit HTTP://
            filename = "http://#{filename}"
            @baseurl = filename.last == '/' ? filename[0..-2] : filename
            rescues = 1
            retry
          when 1
            # As a last resort, dump user input to Google
            filename = "http://www.google.de/search?q=#{filename[2..-1].gsub(' ', '+')}&ie=utf-8&oe=utf-8"
            @baseurl = "http://www.google.de"
            rescues = 2
            retry
        end
        # Everything failed. Lets see why.
        @page = Nokogiri::HTML("<body><div class=\"container\">#{e.message.html_safe}</div></body>")
      end

    end

    private
      def reformat
        @page.xpath('//body').children.each do |node|
          node.set_attribute('class', 'container')
        end
      end

      def skim
        remove_by_xpath('//script')
        remove_by_xpath('//object')
        remove_by_xpath('//noscript')
        remove_by_xpath('//noframes')
        remove_by_xpath('//applet')
        remove_by_xpath('//meta')
        remove_by_xpath('//link')
        remove_by_xpath('//iframe')
        remove_by_xpath('//style')
        remove_by_xpath('//base')
        remove_by_xpath('//basefont')
        remove_by_xpath('//font')
        remove_by_xpath('//form')
        remove_by_xpath('//frameset')
        remove_by_xpath('//frame')
        remove_by_xpath('//comment()')
        remove_by_xpath('//nav')

        strip_attributes(@page)
        relink
        character_count = analyze(@page)
        keep(@page.xpath('//body'), character_count)
        remove_by_xpath('//*[@data-del=1]')
      end

      def keep(node, count)
        iteration = node.children
        cutoff = (1.0 / iteration.count) * 0.1
        iteration.each do |n|
          if n['data-cc'] == '0.0'
            n['data-del'] = '1'
          else
            unless (n.description && n.description.inline?)
              if (n['data-cc'].to_f / count) < cutoff
                n['data-del'] = '1'
              else
                keep(n, n['data-cc'].to_f)
              end
            end
          end
        end
      end

      def remove_by_xpath(xpath)
        if xpath
          @page.xpath(xpath).each do |n|
            n.remove
          end
        end
      end

      def strip_attributes(node)
        node.children.each do |n|
          strip_attributes n
          n.attributes.each do |key, value|
            case key
              when 'href', 'src', 'value'
                # Keep these attributes
              when 'style'
                # Remove hidden/invisible nodes
                if value.content =~ /hidden/ || value.content =~ /display\s*:\s*none/
                  n.remove
                  next
                end
                n.remove_attribute(key)
              else
                # Remove the attribute
                n.remove_attribute(key)
            end
          end
        end
      end

      def relink
        @page.xpath('//a').each do |n|
          if n['href'] =~ /^[a-zA-z]*:\/\//
            n['href'] = "/?link=#{n['href']}"
          else
            if n['href']
              if @baseurl == 'http://www.google.de'
                n['href'] = n['href'][7..-1]
                amp = n['href'].index('&')
                if amp
                  n['href'] = n['href'][0..amp-1]
                end
                n['href'] = "/?link=#{n['href']}"
              else
                n['href'] = n['href'].first == '/' ? "/?link=#{@baseurl}#{n['href']}" : "/?link=#{@baseurl}/#{n['href']}"
              end
            else
              n.remove_attribute('href')
            end
          end
        end
      end

      def analyze(node)
        char_weight = 0
        node.children.each do |n|
          # count characters in the node
          l = n.xpath('text()').text.strip.length
          factor = 1.0

          # weigh tags
          case n.name
          when 'h1'
            factor = 14.0
          when 'h2'
            factor = 12.0
          when 'h3'
            factor = 10.0
          when 'h4'
            factor = 8.0
          when 'h5'
            factor = 6.0
          when 'h6', 'p', 'cite', 'code', 'em', 'strong', 'samp', 'pre', 'blockquote'
            factor = 4.0
          when 'b', 'i', 'u'
            factor = 2.0
          when 'ul', 'ol', 'dl', 'dir', 'menu'
            factor = 0.5
          when 'li', 'dl'
            factor = 0.25
          when 'a'
            if n['href'] =~ /#/
              n.remove
              next
            end
          when 'img'
            l = 0.01
          end
          l_upstream = analyze(n)
          l = (l + l_upstream) * factor
          n['data-cc'] = l.to_f
          char_weight = char_weight + l
        end
        return char_weight
      end
  end
end
