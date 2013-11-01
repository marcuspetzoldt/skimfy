require 'nokogiri'

class Skimfy

  def page=(b)
    @page = b
  end

  def page
    @page
  end

  def initialize(filename)
    @page = Nokogiri::HTML(File.new(filename)) 

    minify
  end

  private
    def minify
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
      warn 'removetextless'
      removetextless(@page)
      node = marktext(@page)
      warn node
      node.set_attribute('style', 'background-color: yellow')
    end

    def remove(tag)
      if tag
        warn "#{tag} entfernen"
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

a = Skimfy.new('dailywtf.html')
puts a.page
