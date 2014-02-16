require 'open3'

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


module Sack
  VERSION = "0.1.0"
  HIGHLIGHT_MATCH_COLOR = :red

  def self.search(search_term)
    klass = choose_best_search_tool
    lines = klass.new(search_term).lines
    transformer = Transformer.new(lines)
    output = transformer.for_color_printing.gsub(/#{search_term}/) do |match|
      match.send(:red)
    end
    STDOUT.puts output
    File.write(File.expand_path("~/.sack_shortcuts"), transformer.shortcut_syntax)
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

  class Search
    attr_accessor :lines, :search_term
    def initialize(search_term)
      @search_term = search_term
      @lines = collect_lines(run_search)
    end

    def collect_lines(input)
      input.map { |i| Line.new(i) }
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
      # @content = content.split("\n")

    end
  end
  class Line
    attr_accessor :line, :filename, :line_number, :description
    def initialize(line)
      @line = line
      parts = split(line)
      @filename = File.expand_path(parts[:filename])
      @line_number = parts[:line_number]
      @description = parts[:description]

    end

    def split(line)
      line.match(%r{^(?<filename>.+)
                    :(?<line_number>\d+)
                    :(?<description>.*)$}x)
    end

  end

  class Transformer
    def initialize(lines)
      @lines = lines
    end

    def unique_files
      @unique_files ||= @lines.map(&:filename).uniq
    end

    def for_color_printing
      @result = []
      @count = 1
      unique_files.each do |file|
        @result << "#{file}\n".green
        @result << @lines.select { |i| i.filename == file}.map do |l|
          row = ["   ", "[#{@count}]".blue.bold, l.line_number.rjust(3), ":", l.description[0..199], "\n"].join(' ')
          @count += 1
          row
        end
        @result << "\n"
      end
        @result.join
    end

    def shortcut_syntax
      @lines.map do |l|
        [l.line_number, l.filename].join(' ') + "\n"
      end.join
    end
  end

end