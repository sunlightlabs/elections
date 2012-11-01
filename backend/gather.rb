#!/usr/bin/env ruby

require 'bundler/setup'

require 'csv'
require 'curb'
require 'oj'
require 'json'

def main
  options = {}

  ARGV[0..-1].each do |arg|
    key, value = arg.split '='
    if key != "" and value != ""
      options[key.downcase.to_sym] = value
    end
  end

  houses = {}
  senates = {}

  CSV.foreach("data/endorsements.csv", "r") do |row|
    entity_id = row[0]
    
    details = details_for(entity_id, options)
    metadata = details['metadata']

    seat = metadata['seat']
    if (seat !~ /^federal/) or (seat !~ /(house|senate)/)
      puts "[#{entity_id}] Incorrect seat: #{seat}"
      exit
    end


    if metadata['district'] and metadata['district'] != ""
      district = metadata['district'].split("-")[1]
      chamber = "house"
    else
      district = nil
      chamber = "senate"
    end

    
    candidate = {
      # basic bio
      chamber: chamber,
      state: metadata['state'],
      district: district,
      party: metadata['party'],
      entity_id: metadata['entity'],
      incumbent: metadata['seat_status'].upcase == 'I',

      # maybe
      bio_url: metadata['bio_url'],
      photo_url: metadata['photo_url'],

      # money
      money: details['totals']['2012'],

      # incumbents
      bioguide_id: metadata['bioguide_id']
    }

    if chamber == "house"
      full_district = [candidate[:state], candidate[:district]].join "-"
      houses[full_district] ||= []
      houses[full_district] << candidate
    elsif chamber == "senate"
      senates[candidate[:state]] ||= []
      senates[candidate[:state]] << candidate
    end
  end

  districts = {}
  houses.each do |district, candidates|
    state = district.split("-").first

    districts[district] ||= []
    districts[district] += candidates
    districts[district] += (senates[state] || [])
  end

  districts.each do |district, candidates|
    write_json output_for(district), candidates
  end

  puts "Processed #{houses.size} House districts."
  puts "Processed #{senates.size} Senate districts."
  puts
  puts "Wrote #{districts.size} district files."
end


def details_for(entity_id, options = {})
  url = url_for entity_id, options[:key]
  destination = cache_for entity_id

  download url, options.merge(json: true, destination: destination)
end

def url_for(entity_id, api_key)
  "http://transparencydata.com/api/1.0/entities/#{entity_id}.json?apikey=#{api_key}"
end

def cache_for(entity_id)
  "cache/#{entity_id}.json"
end

def output_for(district)
  "data/districts/#{district}.json"
end


# utils

def download(url, options = {})
  # cache if caching is opted-into, and the cache exists
  if !options[:force] and options[:destination] and File.exists?(options[:destination])
    puts "Cached #{url} from #{options[:destination]}, not downloading..." if options[:debug]
    
    body = File.read options[:destination]
    body = Oj.load(body) if options[:json]
    body

  # download, potentially saving to disk
  else
    puts "Downloading #{url} to #{options[:destination] || "[not cached]"}..." if options[:debug]
    
    body = begin
      curl = Curl::Easy.new url
      curl.follow_location = true # follow redirects
      curl.perform
    rescue Curl::Err::ConnectionFailedError, Curl::Err::PartialFileError, 
      Curl::Err::RecvError, Timeout::Error, Curl::Err::HostResolutionError, 
      Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::ENETUNREACH, Errno::ECONNREFUSED
      puts "Error curling #{url}"
      nil
    else
      curl.body_str
    end

    body = Oj.load(body) if options[:json]

    # returns true or false if a destination is given
    if options[:destination]
      return nil unless body

      if options[:json] # body will be parsed
        write options[:destination], JSON.pretty_generate(body)
      else
        write options[:destination], body
      end
    end
    
    body
  end
end

def write(destination, content)
  FileUtils.mkdir_p File.dirname(destination)
  File.open(destination, 'w') {|f| f.write content}
end

def write_json(destination, object)
  write destination, JSON.pretty_generate(object)
end

main