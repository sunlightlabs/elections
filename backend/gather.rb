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
    
    candidate = candidate_for entity_id, options
    
    endorsement = row[4]
    rating = row[5]
    grade = row[6]
    
    if rating and rating != ""
      type = "rating"
      value = rating
    elsif grade and grade != ""
      type = "grade"
      value = grade
    else
      type = "endorsement"
      value = endorsement
    end

    endorsement = {
      name: row[3],
      type: type,
      value: value
    }

    if candidate[:chamber] == "house"
      full_district = [candidate[:state], candidate[:district]].join "-"
      houses[full_district] ||= {}
      houses[full_district][candidate[:entity_id]] ||= candidate
      houses[full_district][candidate[:entity_id]][:endorsements] ||= []
      houses[full_district][candidate[:entity_id]][:endorsements] << endorsement
    elsif candidate[:chamber] == "senate"
      senates[candidate[:state]] ||= {}
      senates[candidate[:state]][candidate[:entity_id]] ||= candidate
      senates[candidate[:state]][candidate[:entity_id]][:endorsements] ||= []
      senates[candidate[:state]][candidate[:entity_id]][:endorsements] << endorsement
    end
  end


  # go through house and senate districts and 
  # bunch them up by all races relevant to a district

  districts = {}
  houses.each do |district, candidates|
    state = district.split("-").first

    districts[district] ||= []
    districts[district] += candidates.values
    districts[district] += (senates[state] || {}).values
  end

  districts.each do |district, candidates|
    write_json output_for(district), candidates
  end

  puts "Processed #{houses.size} House districts."
  puts "Processed #{senates.size} Senate districts."
  puts
  puts "Wrote #{districts.size} district files."
end


def candidate_for(entity_id, options = {})
  url = url_for entity_id, options[:key]
  destination = cache_for entity_id

  details = download url, options.merge(destination: destination)

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
    entity_id: metadata['entity'],

    # basic bio
    chamber: chamber,
    state: metadata['state'],
    district: district,
    party: metadata['party'],
    incumbent: metadata['seat_status'].upcase == 'I',

    # maybe
    bio_url: metadata['bio_url'],
    photo_url: metadata['photo_url'],

    # incumbents
    bioguide_id: metadata['bioguide_id']
  }

  url = fec_summary_url_for entity_id, options[:key]
  destination = cache_for entity_id, :fec_summary
  candidate[:fec_summary] = download url, options.merge(destination: destination)

  url = industries_url_for entity_id, options[:key]
  destination = cache_for entity_id, :industries
  industries = download url, options.merge(destination: destination)
  candidate[:industries] = process_industries industries

  candidate
end


def url_for(entity_id, api_key)
  "http://transparencydata.com/api/1.0/entities/#{entity_id}.json?apikey=#{api_key}"
end

def fec_summary_url_for(entity_id, api_key)
  "http://transparencydata.com/api/1.0/aggregates/pol/#{entity_id}/fec_summary.json?apikey=#{api_key}"
end

def industries_url_for(entity_id, api_key)
  "http://transparencydata.com/api/1.0/aggregates/pol/#{entity_id}/contributors/industries.json?apikey=#{api_key}"
end

def cache_for(entity_id, function = :details)
  "cache/#{entity_id}-#{function}.json"
end

def output_for(district)
  "data/districts/#{district}.json"
end

# remove should_show_entity field, clean up name
def process_industries(industries)
  industries.map do |industry|
    {
      count: industry['count'],
      amount: industry['amount'],
      id: industry['id'],
      name: industry_name(industry['name'])
    }
  end
end

def industry_name(name)
  name
    .gsub("/", " / ")
    .gsub("-", " - ")
    .downcase.split(" ")
    .map(&:capitalize)
    .join(" ")
    .gsub(" / ", "/")
    .gsub(" - ", "-")
end

# utils

def download(url, options = {})
  options[:json] = true

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