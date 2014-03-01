require 'open3'

module Sack
  VERSION = "0.3.0"
  HIGHLIGHT_MATCH_COLOR = :red
  SHORTCUTS_FILE = ENV.fetch('SACK_SHORTCUTS') { File.expand_path("~/.sack_shortcuts") }

  def self.search(search_term)
    klass = choose_best_search_tool
    lines = klass.new(search_term).lines
    transformer = Transformer.new(lines)
    color_output = transformer.for_color_printing(search_term)
      begin
        STDOUT.puts color_output
      rescue Errno::EPIPE
        exit(74)
      end
    File.write(SHORTCUTS_FILE, transformer.shortcut_syntax)
  end

  def self.choose_best_search_tool
    case
    when available?('ag');then Ag
    when available?('ack');then Ack
    when available?('grep');then Grep
    end
  end

  def self.available?(name)
    _, status = Open3.capture2("which #{name}")
    status.exitstatus == 0
  end

  class Stdin
    attr_accessor :lines
    def self.search(io)
      std = new(io.dup)
      trace = Sack::Stack::Parser.new(std.lines).ruby_trace
      exit(1) if trace.empty?
      transformer = Sack::Transformer.new(trace)
      output = transformer.shortcut_syntax
      color_output = transformer.for_color_printing
      begin
        STDOUT.puts color_output
      rescue Errno::EPIPE
        exit(74)
      end
      File.write(SHORTCUTS_FILE, output)
    end

    def initialize(io)
      @lines = io
    end
  end

  module Stack
    class Parser
      attr_accessor :lines
      def initialize(lines)
        @lines = lines
      end

      def ruby_trace
        @ruby_stack ||= @lines.map do |line|
          begin
            Line.new(line)
          rescue
            # rescue bad lines
            next
          end
        end.compact

        Array(@ruby_stack)
      end
    end

    class Line
      attr_accessor :line, :filename, :line_number, :match_index, :description
      def initialize(line)
        @line = line
        parts = split(line)
        @filename = parts[:filename]
        @line_number = parts[:line_number]
        @match_index = 0
        @description = parts[:description]
      end

      def split(line)
        line.match(%r{((?<filename>/.*/.*):(?<line_number>\d+)):(?<description>.*)$})
      end
    end
  end

  class Search
    attr_accessor :lines, :search_term
    def initialize(search_term)
      @search_term = search_term
      @lines = collect_lines(run_search)
    end

    def collect_lines(input)
      input.map do |i|
        begin
          Line.new(i, search_term)
        rescue
          next
        end
      end
    end

    def command
      raise(ArgumentError, "Must be implemented in child class")
    end

    def cmd
      "#{command} '#{search_term}'"
    end

    def run_search
      %x{#{cmd}}.chomp.remove_non_ascii.split("\n")
    end
  end

  class Ack < Search
    def command
      "ack -i"
    end
  end

  class Ag < Search
    def command
      "ag -i"
    end
  end

  class Grep < Search
    def command
      "grep -ir --line-number"
    end

    def cmd
      "#{command} '#{search_term}' ."
    end
  end

  class Jumper
    attr_accessor :content, :line
    def initialize(content)
      file = File.new(Dir["ack.formatted"].first)
      @line = file.readlines[1]
    end
  end

  class Line
    attr_accessor :line, :filename, :line_number, :description, :match_index
    def initialize(line, search_term)
      @line = line
      parts = split(line)
      @filename = [Dir.pwd, parts[:filename]].join(File::SEPARATOR)
      @line_number = parts[:line_number]
      @description = parts[:description]
      @match_index = @description.index(%r{#{search_term}}) || 0
    end

    def split(line)
      os = {}
      os[:filename], os[:line_number], os[:description] = line.split(':', 3)
      os
    end

  end

  class Transformer
    def initialize(lines)
      @lines = lines
    end

    def unique_files
      @unique_files ||= @lines.map(&:filename).uniq
    end

    def for_color_printing(search_term = '')
      @result = []
      @count = 1
      unique_files.each do |file|
        @result << "#{file}\n".green
        @result << @lines.select { |i| i.filename == file}.map do |l|

          line_number = l.line_number.rjust(3)
          count = "[#{@count}]".blue.bold

          if l.respond_to?(:description)
            description = l.description[0..199].gsub(/#{search_term}/) do |match|
              match.send(:red)
            end
            row = ["   ", count, line_number, ":", String(description), "\n"].compact.join(' ')
          else
            row = ["   ", count, line_number, file, "\n"].compact.join(' ')
          end

          @count += 1
          row
        end
        @result << "\n"
      end
        @result.join
    end

    def shortcut_syntax
      @lines.map do |l|

        index_of_item = ( l.match_index + 1 ).to_s
        middle_portion = [l.line_number, 'col', index_of_item].join(' ')
        [l.filename, middle_portion, l.description].join('|') + "\n"
      end.join
    end
  end
end

class String
  ENCODING_OPTS = {invalid: :replace, undef: :replace, replace: '', universal_newline: true}
  def remove_non_ascii
    self.encode(Encoding.find('ASCII'), ENCODING_OPTS)
  end

  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def black;          colorize(30) end
  def red;            colorize(31) end
  def green;          colorize(32) end
  def brown;          colorize(33) end
  def blue;           colorize(34) end
  def magenta;        colorize(35) end
  def cyan;           colorize(36) end
  def gray;           colorize(37) end
  def bg_black;       colorize(40) end
  def bg_red;         colorize(41) end
  def bg_green;       colorize(42) end
  def bg_brown;       colorize(43) end
  def bg_blue;        colorize(44) end
  def bg_magenta;     colorize(45) end
  def bg_cyan;        colorize(46) end
  def bg_gray;        colorize(47) end
  def bold;           colorize(1) end
  def reverse_color;  colorize(7) end
end

