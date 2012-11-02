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

  not_candidates = [
    "6ee0ac519a08490594ec3fbce3ce3d8e" # Ron Paul
  ]

  senate_races = [
    "AZ", "CA", "CT", "DE", "FL", "HI", "IN", "ME", "MD", 
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NJ", 
    "NM", "NY", "ND", "OH", "PA", "RI", "TN", "TX", "UT", 
    "VT", "VA", "WA", "WV", "WI", "WY"
  ]

  i = 0
  CSV.foreach("data/endorsements.csv", "r") do |row|
    i += 1
    next if i == 1

    entity_id = row[0]
    next if not_candidates.include?(entity_id)
    
    candidate = candidate_for entity_id, options

    if candidate[:senate_class] and (candidate[:senate_class] != "") and (candidate[:senate_class] != "I")
      puts "[#{entity_id}] Skipping senator, not up for election"
      next
    end

    if candidate[:seat_status] == ""
      puts "[#{entity_id}] Skipping, not up for election"
      next
    end
    
    candidate_name = row[1]

    name = row[2]
    endorsement = row[8]
    rating = row[9]
    grade = row[10]

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
      name: name,
      type: type,
      value: value
    }

    if candidate[:chamber] == "house"
      full_district = [candidate[:state], candidate[:district]].join "-"
      houses[full_district] ||= {}
      houses[full_district][candidate[:entity_id]] ||= candidate
      houses[full_district][candidate[:entity_id]][:name] = candidate_name # overwrite each time
      houses[full_district][candidate[:entity_id]][:endorsements] ||= []
      houses[full_district][candidate[:entity_id]][:endorsements] << endorsement
    elsif candidate[:chamber] == "senate"
      if senate_races.include?(candidate[:state])
        senates[candidate[:state]] ||= {}
        senates[candidate[:state]][candidate[:entity_id]] ||= candidate
        senates[candidate[:state]][candidate[:entity_id]][:name] = candidate_name # overwrite each time
        senates[candidate[:state]][candidate[:entity_id]][:endorsements] ||= []
        senates[candidate[:state]][candidate[:entity_id]][:endorsements] << endorsement
      end
    end
  end


  # go through house and senate districts and 
  # bunch them up by all races relevant to a district

  districts = {}
  houses.each do |district, candidates|
    state = district.split("-").first

    districts[district] ||= {}
    districts[district][:house] = candidates.values
    districts[district][:senate] = (senates[state] || {}).values
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

    prez_house = [
      "d4407eb6730341758ad300fc09f6a8a8", # Kucinich
      "86b2f97e11fc4a87be8d621fd46fc7e6"  # Bachmann
    ]
    
    if prez_house.include?(entity_id)
      seat = "federal:house"
    else
      puts "[#{entity_id}] Incorrect seat: #{seat}"
      exit
    end

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
    state_name: state_map[metadata['state']],
    district: district,
    party: metadata['party'],
    incumbent: metadata['seat_status'].upcase == 'I',

    # maybe
    bio_url: metadata['bio_url'],
    photo_url: metadata['photo_url'],

    seat_status: metadata['seat_status'],

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

  if candidate[:bioguide_id] and (candidate[:bioguide_id] != "")
    url = sunlight_url_for candidate[:bioguide_id], options[:key]
    destination = cache_for entity_id, :sunlight
    result = download url, options.merge(destination: destination)
    senate_class = result['response']['legislator']['senate_class']
    candidate[:senate_class] = senate_class
  end

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

def sunlight_url_for(bioguide_id, api_key)
  "http://services.sunlightlabs.com/api/legislators.get.json?apikey=#{api_key}&all_legislators=1&bioguide_id=#{bioguide_id}"
end

def cache_for(entity_id, function = :details)
  "cache/#{entity_id}/#{function}.json"
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

def state_map
  @state_map ||= {
    "AL" => "Alabama",
    "AK" => "Alaska",
    "AZ" => "Arizona",
    "AR" => "Arkansas",
    "CA" => "California",
    "CO" => "Colorado",
    "CT" => "Connecticut",
    "DE" => "Delaware",
    "DC" => "District of Columbia",
    "FL" => "Florida",
    "GA" => "Georgia",
    "HI" => "Hawaii",
    "ID" => "Idaho",
    "IL" => "Illinois",
    "IN" => "Indiana",
    "IA" => "Iowa",
    "KS" => "Kansas",
    "KY" => "Kentucky",
    "LA" => "Louisiana",
    "ME" => "Maine",
    "MD" => "Maryland",
    "MA" => "Massachusetts",
    "MI" => "Michigan",
    "MN" => "Minnesota",
    "MS" => "Mississippi",
    "MO" => "Missouri",
    "MT" => "Montana",
    "NE" => "Nebraska",
    "NV" => "Nevada",
    "NH" => "New Hampshire",
    "NJ" => "New Jersey",
    "NM" => "New Mexico",
    "NY" => "New York",
    "NC" => "North Carolina",
    "ND" => "North Dakota",
    "OH" => "Ohio",
    "OK" => "Oklahoma",
    "OR" => "Oregon",
    "PA" => "Pennsylvania",
    "PR" => "Puerto Rico",
    "RI" => "Rhode Island",
    "SC" => "South Carolina",
    "SD" => "South Dakota",
    "TN" => "Tennessee",
    "TX" => "Texas",
    "UT" => "Utah",
    "VT" => "Vermont",
    "VA" => "Virginia",
    "WA" => "Washington",
    "WV" => "West Virginia",
    "WI" => "Wisconsin",
    "WY" => "Wyoming"
  }
end

main