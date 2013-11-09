# encoding: UTF-8
module SkimfyCore

  require 'nokogiri'
  require 'open-uri'
  require 'openssl'
  require 'net/http'
  require 'fastimage'

  class Skimfy

    # Viscosity
    MU = 1.5
    CUTOFF = 11

    def page=(b)
      @page = b
    end

    def page
      @page
    end

    def body
      @page.xpath('//body').children
    end

    def encoding
      @page.meta_encoding || 'utf-8'
    end

    def initialize(filename)

      return if filename.blank?

      rescues = 0
      @baseurl = filename.last == '/' ? filename[0..-2] : filename

      begin
        @page = Nokogiri::HTML(open(filename, ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE))
        if @page.encoding.nil?
          @page.encoding = 'utf-8'
        end
        skim
      rescue Errno::ENOENT, URI::InvalidURIError => e
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
      rescue OpenURI::HTTPError
        # Everything failed. Lets see why.
        @page = Nokogiri::HTML("<div class=\"container\">#{e.message.html_safe}</div>")
      end

    end

    private
      def skim
        body = @page.xpath('//body')

        body.xpath('//script').remove
        body.xpath('//object').remove
        body.xpath('//noscript').remove
        body.xpath('//noframes').remove
        body.xpath('//applet').remove
        body.xpath('//meta').remove
        body.xpath('//link').remove
        body.xpath('//iframe').remove
        body.xpath('//style').remove
        body.xpath('//base').remove
        body.xpath('//basefont').remove
        body.xpath('//font').remove
        body.xpath('//form').remove
        body.xpath('//frameset').remove
        body.xpath('//frame').remove
        body.xpath('//comment()').remove
        body.xpath('//nav').remove

        strip_attributes(body)
        flatten(body, 0)
        analyze(body)
        attract(body)
        maximum = max(body)
        normalize(body, maximum)
        cleanup(body)
        remove_images(body)
        relink(body)
      end

      def cleanup(node)
        node.children.each do |n|
          if n['data-cc'] && n['data-cc'].to_i < CUTOFF
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

      def remove_images(node)
        node.xpath('//img').each do |n|
          if n['src'][0..4] == 'http:'
            size = FastImage.size(n['src'])
            if size && size[0] < 300 && size[1] < 300
              n.remove
            else
              if size[0] > 450
                n['width'] = '450px'
              end
            end
          end
        end
      end

      def relink(node)
        node.xpath('//a').each do |n|
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

      def flatten(node, depth)
        blockless = ''
        node.children.each do |n|
          if n.text? || (n.description && n.description.inline?)
            blockless << n.to_s.chomp.gsub(/  */, ' ')
            n.remove
          else
            unless blockless.strip == ''
              n.before("<#{n.parent.name}>#{blockless}</#{n.parent.name}>")
              blockless = ''
            end
            flatten(n, 1)
          end
        end
        if depth == 1
          unless blockless.strip == ''
            node.add_child("<#{node.name}>#{blockless}</#{node.name}>")
          end
          case node.name
          when 'ol', 'ul', 'dl', 'dir', 'menu', 'table', 'tr', 'tbody', 'thead', 'tfoot'
            # ignore
          else
            node.before(node.children)
            node.remove
          end
        end
      end

      def max(node)
        maximum = 0
        node.children.each do |n|
          m = max(n)
          if n['data-cc']
            weight = n['data-cc'].to_f
            m = m > weight ? m : weight
          end
          maximum = m > maximum ? m : maximum
        end
        maximum
      end

      def normalize(node, norm)
        node.children.each do |n|
          if n['data-cc']
            x = n['data-cc'].to_f + n['data-gr'].to_f
            x = ((x / norm) * 15).to_i
            n['data-cc'] = x > 15 ? '15' : x.to_s
          else
            n['data-cc'] = n.parent['data-cc']
          end
          normalize(n, norm)
        end
      end

      def analyze(node)
        total_weight = 0
        node.children.each do |n|
          # count characters in the node
          l = n.xpath('text()').inner_text.strip.length
          factor = 1.0

          # weigh tags
          case n.name
          when 'h1'
            factor = 6.0
          when 'h2'
            factor = 5.0
          when 'h3'
            factor = 4.0
          when 'h4'
            factor = 3.0
          when 'h5'
            factor = 2.0
          when 'h6', 'p', 'cite', 'code', 'em', 'strong', 'samp', 'pre', 'blockquote'
            factor = 2.0
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
          weight = l.to_f * factor
          upstream_weight = analyze(n) * factor
          n['data-gr'] = '0.0'
          n['data-cc'] = weight + upstream_weight
          total_weight = total_weight + weight + upstream_weight
        end
        total_weight
      end

      def attract(node)
        node.children.each do |n|
          if n['data-cc']
            w = n['data-cc'].to_f
            sibling = n
            loop do
              sibling = sibling.next_sibling
              if sibling && sibling['data-cc']
                w = w / MU
                sibling['data-gr'] = sibling['data-gr'].to_f + w
              end
              break unless w > 0 && sibling
            end
            w = n['data-cc'].to_f
            sibling = n
            loop do
              sibling = sibling.previous_sibling
              if sibling && sibling['data-cc']
                w = w / MU
                sibling['data-gr'] = sibling['data-gr'].to_f + w
              end
              break unless w > 0 && sibling
            end
          end
        end
      end

  end
end
