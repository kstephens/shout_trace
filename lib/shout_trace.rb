
# ShoutTrace - a Ruby backtrace annotator and editor service.
#
# ShoutTrace::Annotator converts Ruby stack traces from logfiles
# and web server errors and translates them into
# localhost URLs which can be used to drive a programmer's editor.
#
# Author: http://kurtstephens.com
module ShoutTrace
  HOST = 'localhost' unless defined? HOST
  PORT = 3333 unless defined? PORT
end # module

require 'shout_trace/annotator'

