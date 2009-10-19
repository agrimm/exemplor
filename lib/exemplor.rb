require 'rubygems' # TODO: remove
require 'orderedhash'
require 'yaml'

module Exemplor
  
  def self.version() File.read(__FILE__.sub('lib/exemplor.rb','VERSION')) end
  
  class ExampleDefinitionError < StandardError ; end
    
  class Check
    
    attr_reader :expectation, :value
    
    def initialize(name, value)
      @name  = name
      @value = value
    end
    
    def [](disambiguate)
      @disambiguate = disambiguate
    end
    
    def name
      @name + (@disambiguate ? " #{@disambiguate}" : '')
    end
    
    def is(expectation)
      @expectation = expectation
    end
    
    def status
      return :info unless defined? @expectation
      @value == @expectation ? :success : :failure
    end
    
    def success?
      status == :success
    end
    
    def failure?
      status == :failure
    end
    
    def info?
      status == :info
    end
    
  end
  
  class Example
    
    class << self
      
      alias_method :helpers, :class_eval
      attr_accessor :setup_block
      
      def setup(&blk) self.setup_block = blk end
      
    end
    
    attr_accessor :_checks
    
    def initialize
      @_checks = []
    end
    
    # fragile. doesnt work with calls like
    # Check(get('/'))
    # Check foo
    def Check(value)
      file, line_number = caller.first.match(/^(.+):(\d+)/).captures
      line = File.read(file).map[line_number.to_i - 1]
      name = line[/Check\((.+?)\)/,1]
      check = Check.new(name, value)
      _checks << check
      check
    end
    
  end
  
  class Examples
    
    attr_writer :setup_block
    
    def initialize
      @examples = OrderedHash.new
    end
    
    def add(name, &body)
      @examples[name] = body
    end
    
    def run(patterns)
      # unoffically supports multiple patterns
      patterns = Regexp.new(patterns.join('|'))
      @examples.each do |name, body|
        if name =~ patterns
          status, out = run_example(body)
          print_yaml("#{status_icon(status)} #{name}" => out)
        end
      end
    end
    
    def list(patterns)
      patterns = Regexp.new(patterns.join('|'))
      list = @examples.keys.select { |name| name =~ patterns }
      print_yaml list
    end
    
    def print_yaml(obj)
      out = obj.to_yaml.match(/^--- \n/).post_match
      out = colorize out if $stdout.tty?
      print(out)
    end
    
    # hacky
    def colorize(out)
      require 'term/ansicolor'
      out.split("\n").map do |line|
        case line
        when /^(?:\s{2})?(\(s\))/ 
          start_color(line, :green)
        when /^(?:\s{2})?(\(f\))/ 
          start_color(line, :red)
        when /^(?:\s{2})?(\(e\))/ 
          start_color(line, :red)
        when /^(?:\s{2})?(\(i\))/i
          start_color(line, :blue)
        else          
          line
        end
      end.join("\n") + "\n#{Term::ANSIColor.reset}"
    end
    
    def start_color(line, color)
      "#{Term::ANSIColor.reset}#{Term::ANSIColor.send(color)}#{line}"
    end
    
    def run_example(code)
      status = :info
      env = Example.new
      out = begin
        env.instance_eval(&Example.setup_block) if Example.setup_block
        value = env.instance_eval(&code)
        if env._checks.empty?
          value
        else
          status = :infos if env._checks.all? { |check| check.info? }
          status = :success if env._checks.all? { |check| check.success? }
          status = :fail if env._checks.any? { |check| check.failure? }          
          render_checks(env._checks)
        end
      rescue Object => error
        status = :error
        render_error(error)
      end
      [status, out]
    end
    
    def render_checks(checks)
      failure = nil
      out = OrderedHash.new
      checks.each do |check|
        failure = check if check.failure?
        break if failure
       
        out["#{status_icon(check.status)} #{check.name}"] = check.value
      end
      if failure
        fail_out = out["#{status_icon(failure.status)} #{failure.name}"] = OrderedHash.new
        fail_out['expected'] = failure.expectation
        fail_out['actual'] = failure.value
      end
      out
    end
    
    def render_error(error)
      out = OrderedHash.new
      out['class'] = error.class.name
      out['message'] = error.message
      out['backtrace'] = error.backtrace
      out
    end
    
    def status_icon(status)      
      icon = status == :infos ? '(I)' : "(#{status.to_s.slice(0,1)})"
    end
    
  end
  
  class << self
    
    def examples
      @examples ||= Examples.new
    end
    
  end
  
end

def eg(name = nil, &example)
  return Exemplor::Example if name.nil? && example.nil?
  if name.nil?
     file, line_number = caller.first.match(/^(.+):(\d+)/).captures
     line = File.read(file).map[line_number.to_i - 1]
     name = line[/^\s*eg\s*\{\s*(.+?)\s*\}\s*$/,1] if name.nil?
     raise Exemplor::ExampleDefinitionError, "example at #{caller.first} has no name so must be on one line" if name.nil?
  end
  Exemplor.examples.add(name, &example)
end

at_exit do
  args = ARGV.dup
  if args.delete('--list') || args.delete('-l')
    Exemplor.examples.list(args)
  else
    Exemplor.examples.run(args)
  end
end