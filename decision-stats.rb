#!/usr/bin/env ruby

require 'optparse'
require 'open-uri'
require 'json'

module Decision

  UDSC_ROOT = 'https://migracje.gov.pl/wp-json/udscmap/v1/'
 
  module CaseType
    TEMPORARY_RESIDENCE = 1
    PERMANENT_RESIDENCE = 2
    EU_LONG_TERM_RESIDENCE = 3
  end
    
  module Status
    POSITIVE = 4
    NEGATIVE = 6 
    DISCONTINUATION = 8
  end

  class Stats
    def initialize(options={})
      @options = options

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options]"
        opts.separator ''
        opts.separator 'Options:'
        opts.on('-t TYPE', '--case-type', 'Type of case: temp, perm, eult') do |t|
          unless %w[perm ksp temp kcp eult].include?(t.downcase)
            raise OptionParser::InvalidArgument.new("#{t} is a not valid value for --case-type")
          end
          @options[:caseType] = case_type(t)
        end
        opts.on('-y YEAR', '--year', 'Year of stats: from 2010 to current') do |y|
          unless (2010..Date.today.year).include?(y.to_i)
            raise OptionParser::InvalidArgument.new("Stats are available from 2010 to current year only")
          end
          @options[:year] = y
        end
        opts.on('-f FILE', '--filters-file', 'JSON file with additional filters:',
                '"ageFrom", "ageTo", "gender" (M/F),',
                '"country" (ISO 3166-1 alpha-2 code)') do |f|
          extra_options = JSON.load(File.read(File.expand_path(f))) #rescue {}
          @options = extra_options.transform_keys(&:to_sym).merge(@options)
        end
        opts.on('-F JSON', '--filters', 'JSON string with additional filters,',
                'the same as in file; whole string',
                'must be in single quotes:',
                '\'{"ageTo": 18, "gender": "F"}\''.magenta) do |s|
          extra_options = JSON.load(s) #rescue {}
          @options = extra_options.merge(@options) # we have to give priority to explicit CLI args
        end
        opts.separator ''
        opts.separator 'By default, it gets stats for permanent residence decisions in the current year.'
        opts.separator ''
        opts.separator "Written by Nick Saukin <me@nsauk.in>. Source data © 2010-#{Date.today.year} UDSC."
      end

      begin
        parser.parse(ARGV)
      rescue OptionParser::MissingArgument, OptionParser::InvalidArgument, JSON::ParserError => e
        puts "Error: #{e.message}".bold
        exit 1
      end

      @options[:year] = Date.today.year unless (2010..Date.today.year).include?(@options[:year].to_i)
      @options[:caseType] ||= 2
    end
  
    def call
      load_decisions
      process_decisions
    end

    def print
      puts [Decision::CaseType.constants.find do |sym|
        Decision::CaseType.const_get(sym) == @options[:caseType]
      end, @options[:year]].join(' ').bold
      if @options.keys.size > 2
        extra_options = @options.reject { |k,v| %i[caseType year].include?(k) }
        puts "Applied filters: #{JSON.generate(extra_options)}"
      end
      call
      puts ['Institution'.ljust(30), 'Total', 'Denied', '% ▲'].join("\t").underline
      @results.map do |row|
        row[0] = row[0].ljust(30)
        puts colorize_by_value(row)
      end
      nil
    end
  
    def case_type(str)
      case str.downcase
      when 'kcp', 'temp'
        CaseType::TEMPORARY_RESIDENCE
      when 'ksp', 'perm'
        CaseType::PERMANENT_RESIDENCE
      when 'eult'
        CaseType::EU_LONG_TERM_RESIDENCE
      else
        CaseType::PERMANENT_RESIDENCE
      end
    end

    def load_json(url)
      str = open(url).read
      str = clear_json(str)
      JSON.load(str)
    end
    
    def clear_json(str)
      str.split("\n").last # sometimes we get PHP warnings in first N lines
    end

    def load_decisions
      @institutions = load_json("#{UDSC_ROOT}institution/?authorityCode=WOJ,WSA,MIN")
      
      filter = {groupBy: "institution,decisionMarker",
                fields: "institution,decisionMarker,total",
                orderBy: "total", order: "desc"}
      filter = @options.merge!(filter)
      @decisions = load_json("#{UDSC_ROOT}decisions/poland/?#{URI.encode_www_form(filter)}")
    end
  
    def process_decisions
      @results = @decisions.group_by { |d| d['institution'] }.map do |k,v|
        name = @institutions.find { |i| i['id'] == k }['name']
        total = v.sum { |d| d['total'] }
        negative = v.find { |d| d['decisionMarker'] == Status::NEGATIVE }&.dig('total') || 0
        probability = (100 * negative / total.to_f).round(2)
        [name, total, negative, probability]
      end.sort_by(&:last)
    end

    def colorize_by_value(row)
      median = @results.map(&:last).median
      return row.join("\t").red if row.last > median ** 1.5
      return row.join("\t").green if row.last < median / 1.5
      row.join("\t")
    end

  end
end

class String
  def red;            "\e[91m#{self}\e[0m" end
  def green;          "\e[92m#{self}\e[0m" end
  def yellow;         "\e[93m#{self}\e[0m" end
  def blue;           "\e[94m#{self}\e[0m" end
  def magenta;        "\e[95m#{self}\e[0m" end
  def cyan;           "\e[96m#{self}\e[0m" end
  def white;          "\e[97m#{self}\e[0m" end

  def bg_black;       "\e[40m#{self}\e[0m" end
  def bg_red;         "\e[41m#{self}\e[0m" end
  def bg_green;       "\e[42m#{self}\e[0m" end
  def bg_brown;       "\e[43m#{self}\e[0m" end
  def bg_blue;        "\e[44m#{self}\e[0m" end
  def bg_magenta;     "\e[45m#{self}\e[0m" end
  def bg_cyan;        "\e[46m#{self}\e[0m" end
  def bg_gray;        "\e[47m#{self}\e[0m" end
  
  def bold;           "\e[1m#{self}\e[22m" end
  def italic;         "\e[3m#{self}\e[23m" end
  def underline;      "\e[4m#{self}\e[24m" end
  def blink;          "\e[5m#{self}\e[25m" end
  def reverse_color;  "\e[7m#{self}\e[27m" end
  def strikethrough;  "\e[9m#{self}\e[27m" end
end

class Array
  def median
    return nil if self.empty?
    sorted = self.sort
    len = sorted.length
    (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
  end
end

Decision::Stats.new.print if __FILE__ == $0
