module SkimfyCore

  require 'nokogiri'
  require 'open-uri'

  class Skimfy

    def page=(b)
      @page = b
    end

    def page
      @page.xpath('//body').children
    end

    def initialize(filename)
      begin
        @page = Nokogiri::HTML(open(filename))
        skim
        reformat
      rescue Exception => e
        unless filename =~ /^.*:\/\//
          filename = "http://#{filename}"
          retry
        end
        @page = Nokogiri::HTML("<body><div class=\"container\">#{e.message}</div></body>")
      end

    end

    private
      def reformat
        @page.xpath('//body').children.each do |node|
          node.set_attribute('class', 'container')
        end
      end
      def skim
        remove('script')
        remove('noscript')
        remove('applet')
        remove('meta')
        remove('link')
        remove('form')
        remove('iframe')
        remove('style')
        remove('comment()')

        unstyle(@page)
        unexternallink
        removetextless(@page)
        node = marktext(@page)
        node.set_attribute('style', 'background-color: yellow')
      end

      def remove(tag)
        if tag
          @page.xpath("//#{tag}").each do |n|
            n.remove
          end
        end
      end

      def removetextless(node)
        node.children.each do |n|
          removetextless(n)
        end
        if node.children.count == 0
          node.remove unless node.text =~ /[A-Za-z]/
        end
      end

      def unstyle(node)
        node.children.each do |n|
          unstyle n
          n.attributes.each do |key,|
            n.remove_attribute(key) unless key == 'href'
          end
        end
      end

      def unexternallink
        @page.xpath('//a').each do |n|
          if n['href'] =~ /^.*:\/\//
            n.remove
          end
        end
      end

      def marktext(node)
        length = node.xpath('text()').text.length
        longest_node = node
        node.children.each do |n|
          l = marktext(n)
          if l.inner_text.length > length
            longest_node = l
          end
        end
        return longest_node
      end
  end
end
