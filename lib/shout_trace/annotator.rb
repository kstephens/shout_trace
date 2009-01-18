# kurt@cashnetusa.com 2007/03/16

require 'shout_trace'

module ShoutTrace

# Annotator analyizes strings for lines
# matching "file:line" and creates HTML <a href> links that
# drive a localhost ShoutTrace::Server which will intern
# open a file in a programmer's editor.
#
# This is helpful for diagnosing errors in remote application
# such as Rails or Merb applications.
#
class Annotator
  # The host of the link.
  # Defaults to HOST.
  attr_accessor :host

  # The port of the link.
  # Defaults to PORT.
  attr_accessor :port

  # Additional query parameters for the generated URL.
  # Defaults to nil.
  attr_accessor :query

  # The link target, use for opening new brower windows.
  # Default to 'shout_trace_file'
  attr_accessor :link_target


  def initialize
    @host = HOST
    @port = PORT
    @query = nil
    @link_target = 'shout_trace_file'
  end


  # Replaces file:line patterns in a string with html links. 
  def annotate(string, opt = { })
    return string unless string
    string = string.to_s
    # string = 4
    out = ''
    while md = /((^|\n)\s*)([^:\n]+?):(\d+)(:in `|\s*(\n|$))/.match(string)
      pre = md.pre_match + md[1]
      out += opt[:html] ? html_escape(pre) : pre
      out += make_link(md[3] + ':' + md[4], md[3], md[4].to_i, opt)
      out += opt[:html] ? html_escape(md[5]) : md[5]
      string = md.post_match
    end
    out += opt[:html] ? html_escape(string) : string
    
    out
  end


  # Creates a link for string to a file:line.
  def make_link(string, file, line, opt = { })
    # Clean up path.
    file = file.gsub('//', '/')
    if opt[:abspath]
      file = File.expand_path(file)
    end

    # Scroll to a line that is before actual line,
    # so user gets some context.
    target_line = line - 5
    target_line = 1 if target_line < 1

    # Make a title.
    title = opt[:title] || "Go to #{File.basename(file)}:#{line}"

    # Handle funky paths.
    file = file.gsub(%r{([^\-\.\_\/a-z0-9])}i) { |x| '%%%02x' % x[0] }
    file = file.gsub(/\.\./, '%252E%252E')

    # '-' is use to anchor leading '/', even if '/' does not exist. 
    # This allows us to pass relative or absolute paths intact to
    # the ShoutTrace::Server.
    "<a href=\"http://#{host}:#{port}/shout_trace/file/-#{file}/#{line}#{query ? '?' + query : ''}\##{target_line}\" title=\"ShoutTrace: #{title}\"#{@link_target ? " target=\"shout_trace_file\"" : ''}>#{string}</a>"
  end


  # Returns the file:line from a link.
  def unmake_link(path)
    path = path.sub(/^\/shout_trace\/file\/-/, '')
    md = /(.*)\/(\d+)$/.match(path)
    result = md ? [ md[1], md[2].to_i ] : [ nil, nil ]
    if result[0]
      result[0].gsub!('%2E%2E', '..')
      result[0].gsub!(/%([0-9a-f][0-9a-f])/i) { |x| x.to_i(16).chr }
    end
    # STDERR.puts "unmake_link(#{path.inspect}) => #{result.inspect}"
    result
  end


  # Annotates a file.
  def annotate_file(req, res, file, opt = { })
    # STDERR.puts "annotate_file(#{file.inspect})"

    # Copy request parameters to opts.
    query = req.request_uri.query || ''
    query = Hash[*query.split(/[;&]/).collect{|x| x.empty? ? [nil, nil] : x.split('=')}.flatten] || { }
    query = query.keys.inject({ }) { | h, k | h[k.intern] = query[k].to_i; h }
    # STDERR.puts "query = #{query.inspect}"
    opt.merge!(query)
    # STDERR.puts "opt = #{opt.inspect}"

    # STDERR.puts "opt = #{opt.inspect}"

    # Read lines from file.
    if opt[:prev]
      lines = read_lines_before(file, opt[:pos] || 0, opt[:n], opt[:n] * 3 / 4) # Move by 3/4 page.
    else
      lines = read_lines_at(file, opt[:pos] || 0, opt[:n])
    end
    
    # Determine navigation positions.
    pos = (lines[0] && lines[0][0]) || 0
    pos_next = (lines[lines.size * 3 / 4][0]) || 0 # Move by 3/4 page.
    
    # Collect output into new array of lines.
    lineno = 0
    lines = lines.collect do | line |
      lineno += 1
      str = line[1]
      
      # Annotate line for stack traces?
      if opt[:annotate]
        str = annotate(str, :html => true)
      else
        str = html_escape(str)
      end
      
      str = "#{opt[:line] ? html_escape(lineno == opt[:line] ? '=> ' : '   ') : ''}<a name=\"#{lineno}\">#{html_escape(opt[:line] ? ('%6d ' % lineno) : ('%8d ' % line[0]))}</a>#{str}"
      
      # Highlight line?
      if lineno == opt[:line]
        str = "<span style=\"color: orange;\">#{str}</span>"
      end
      
      str
    end
    
    # Create navigation?
    nav = ''
    if opt[:n]
      nav = [ 
             { :text => "|<", :title => "First", :pos => 0,           :prev => nil },
             { :text => "<<", :title => "Prev",  :pos => pos,         :prev => 1   },
             { :text => ">>", :title => "Next",  :pos => pos_next,    :prev => nil },
             { :text => ">|", :title => "Last",  :pos => - 1,         :prev => 1   },
             query[:play] ? 
             { :text => "||", :title => "Pause", :pos => pos, :play => nil } :
             { :text => "=>", :title => "Play",  :pos => pos, :play => 1 } ,
            ]
      
      nav = nav.collect do | nav |
        title = nav[:title] || ''
        nav.delete(:title)
        text = nav[:text] || ''
        nav.delete(:text)
        nav[:n]   ||= opt[:n]   if opt[:n]
        query.merge!(nav)
        uri = "#{req.request_uri.path}?#{query.keys.collect { | k | nav[k] && "#{k}=#{nav[k]};"}}"
        "<a href=\"#{uri}\" title=\"#{title}\">#{h text}</a>"
      end

      nav = nav.collect { | nav | "<td>#{nav}</td>" }
      nav = "<table><tr>#{nav}</tr></table><br />"
    end
    # STDERR.puts "nav = #{nav.inspect}"

    # Generate page.
    out = <<-"END"
    <html>
      <head>
        <title>ShoutTrace - #{file}</title> 
        #{query[:play] ? "<meta http-equiv=\"refresh\" content=\"5;url=#{req.request_uri}\" />" : ''}
      </head>
      <body>
        <h1>#{html_escape(opt[:msg] || '')}</h1>
        #{h file}<br />
        #{nav}
        <code>
        #{lines.join("\n")}
        </code>
      </body>
    </html>
    END

    # STDERR.puts "out = #{out}"
    res['Content-Type'] = 'text/html'
    res.body = out

    out
  end

  
  def read_lines_at(file, pos, n = nil)
    # STDERR.puts "read_lines_at(#{file.inspect}, #{pos.inspect}, #{n.inspect})"

    # Read lines from file.
    lines = [ ]
    File.open(file) do | fh |
      if pos >= 0
        fh.seek(pos, IO::SEEK_SET) rescue nil
      else
        fh.seek(pos, IO::SEEK_END) rescue nil
        fh.readline
      end

      # Read until pos_end or eof.
      until fh.eof? or (n && lines.size >= n)
        line_pos = fh.pos 
        line = [ line_pos, fh.readline ]
        # STDERR.puts "read = #{line.inspect}"
        lines << line
      end
    end

    lines
  end


  def read_lines_before(file, pos, n, back, blksize = 8192)
    # STDERR.puts "read_lines_before(#{file.inspect}, #{pos.inspect}, #{n.inspect}, #{back.inspect}))"
    lines = [ ] 
    back ||= n   

    File.open(file) do | fh |
      if pos < 0
        fh.seek(pos, IO::SEEK_END) rescue nil
        fh.readline
        pos = fh.pos
      end

      pos_end = pos
      while pos >= 0 && lines.size < back
        lines_buf = [ ]
        
        # Backup by a block.
        pos -= blksize
        
        # When to stop reading lines.
        pos_stop = lines[0] ? lines[0][0] : pos_end
        
        # If at beginning of file?
        pos_line = pos
        if pos_line <= 0 
          pos_line = 0
          fh.seek(pos_line, IO::SEEK_SET) rescue nil
        else
          # If not at beginning of file,
          # assume we are at in the middle of a line.
          fh.seek(pos_line, IO::SEEK_SET) rescue nil
          fh.readline 
         end

        # STDERR.puts "seeked to #{pos_line}"
        # STDERR.puts "stop at #{pos_stop}"
        until fh.eof?
          pos_line = fh.pos
          break if pos_line >= pos_stop
          line = [ pos_line, fh.readline ]
          # STDERR.puts "read = #{line.inspect}"
          lines_buf << line
        end

        # Insert new lines read.
        lines = lines_buf + lines

      end

      # Truncate.
      if lines.size > back
        lines = lines[- back .. -1]
      end
      
      # Fill out the buffer.
      if lines.size < n
        fh.seek(pos_end, IO::SEEK_SET) rescue nil
        until fh.eof?
          break if lines.size >= n
          pos_line = fh.pos
          line = [ pos_line, fh.readline ]
          lines << line
        end
      end
    end

    lines
  end


  @@html_map = {
    "<"  => "&lt;",
    ">"  => "&gt;",
    "\"" => "&quo;",
    "&"  => "&amp;",
    " "  => "&nbsp;",
    "\n" => "<br />\n",
  }


  def html_escape(str)
    return str unless str
    str.to_s.gsub(/[<>& \n]/) do | x |
      @@html_map[x] || x
    end
  end
  alias :h :html_escape

end # class


end # module


