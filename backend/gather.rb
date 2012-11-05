#!/usr/bin/env ruby

require 'bundler/setup'

require 'csv'
require 'curb'
require 'oj'
require 'json'

def senate_races
  @senate_races ||= [
    "AZ", "CA", "CT", "DE", "FL", "HI", "IN", "ME", "MD", 
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NJ", 
    "NM", "NY", "ND", "OH", "PA", "RI", "TN", "TX", "UT", 
    "VT", "VA", "WA", "WV", "WI", "WY"
  ]
end

# "AZ-4", "WY-at_large", etc.
def house_races
  @house_races ||= Dir.glob("thumbs/house_images_ac/*").map do |path| 
    File.basename path
  end
end

def bp_house
  @bp_house ||= Oj.load(File.open("ballotpedia/house_candidates.json"))
end

def bp_senate
  @bp_senate ||= Oj.load(File.open("ballotpedia/senate_candidates.json"))
end

def options
  @options ||= load_options
end

def load_options
  options = {}

  ARGV[0..-1].each do |arg|
    key, value = arg.split '='
    if key != "" and value != ""
      options[key.downcase.to_sym] = value
    end
  end

  options
end

def main
  # not_candidates = [
  #   "6ee0ac519a08490594ec3fbce3ce3d8e" # Ron Paul
  # ]
  
  # initialize candidate holders

  senates = {}
  senate_races.each do |race|
    senates[race] = {}
  end

  houses = {}
  house_races.each do |race|
    houses[race] = {}
  end

  print "Reading endorsements..."

  i = 0
  CSV.foreach("data/endorsements.csv", "r") do |row|
    i += 1
    next if i == 1

    print "." if !options[:debug] and (i % 100 == 0)

    entity_id = row[0]
    # next if not_candidates.include?(entity_id)
    
    next unless candidate = candidate_for(entity_id, options)
    
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
      houses[full_district][candidate[:entity_id]] ||= candidate
      houses[full_district][candidate[:entity_id]][:name] = candidate_name # overwrite each time
      houses[full_district][candidate[:entity_id]][:endorsements] ||= []
      houses[full_district][candidate[:entity_id]][:endorsements] << endorsement
    elsif candidate[:chamber] == "senate"
      senates[candidate[:state]][candidate[:entity_id]] ||= candidate
      senates[candidate[:state]][candidate[:entity_id]][:name] = candidate_name # overwrite each time
      senates[candidate[:state]][candidate[:entity_id]][:endorsements] ||= []
      senates[candidate[:state]][candidate[:entity_id]][:endorsements] << endorsement
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

  puts
  puts "Processed #{houses.size} House districts."
  puts "Processed #{senates.size} Senate districts."
  puts
  puts "Wrote #{districts.size} district files."
  

  # guess at what's missing

  if options[:missing]

    missing_house = {}
    missing_senate = {}
  
    houses.each do |district, candidates|
      if candidates.values.size < 2
        missing_house[district] = candidates.values.size
      end
    end

    senates.each do |state, candidates|
      if candidates.values.size < 2
        missing_senate[state] = candidates.values.size
      end
    end

    puts
    puts "#{missing_house.keys.size} incomplete House districts:"
    puts missing_house.inspect
    puts "#{missing_senate.keys.size} incomplete Senate districts"
    puts missing_senate.inspect
  end
end


def candidate_for(entity_id, options = {})
  url = url_for entity_id, options[:key]
  destination = cache_for entity_id

  details = download url, options.merge(destination: destination)

  metadata = details['metadata']

  seat = metadata['seat']
  if (seat !~ /^federal/) or (seat !~ /(house|senate)/)

    prez_house = [
      "d4407eb6730341758ad300fc09f6a8a8",  # Kucinich
      "86b2f97e11fc4a87be8d621fd46fc7e6",  # Bachmann
      "6ee0ac519a08490594ec3fbce3ce3d8e",  # Paul
    ]
    
    if prez_house.include?(entity_id)
      seat = "federal:house"
    else
      puts "[#{entity_id}] Incorrect seat: #{seat}"
      exit
    end

  end

  chamber = seat.split(":")[1]

  state = metadata['state']

  if (chamber == "house") and metadata['district'] and (metadata['district'] != "")
    district = metadata['district'].split("-")[1]
    district = district.to_i.to_s # strip leading 0
  elsif chamber == "senate"
    district = nil
  end

  # figure out if it's an at large, convert 1 to at_large
  if chamber == "house"
    if !house_races.include?([state, district].join("-"))
      if district == "1"
        district = "at_large"
      else
        puts "[#{entity_id}] Error, couldn't find correct district: #{state}-#{district}"
        exit
      end
    end
  end

  if chamber == "senate"
    if !senate_races.include?(state)
      puts "[#{entity_id}] No senate race in state, skipping" if options[:debug]
      return nil
    end
  end

  # validate that this person is running

  unless ballotpedia_name = ballotpedia_name_for(details['name'], chamber, state, district)
    # puts "[#{entity_id}][#{details['name']}] Couldn't find in Ballotpedia, skipping" if options[:skips]
    return nil
  end

  # if it's valid, find a photo
  photo = photo_filename_for ballotpedia_name, chamber, state, district

  candidate = {
    entity_id: metadata['entity'],

    # name and photo
    name: details['name'],

    # basic bio
    chamber: chamber,
    state: state,
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

  # if candidate[:bioguide_id] and (candidate[:bioguide_id] != "")
  #   url = sunlight_url_for candidate[:bioguide_id], options[:key]
  #   destination = cache_for entity_id, :sunlight
  #   result = download url, options.merge(destination: destination)
  #   senate_class = result['response']['legislator']['senate_class']
  #   candidate[:senate_class] = senate_class
  # end
  
  
  # checks to see if this candidate is valid

  # if candidate[:senate_class] and (candidate[:senate_class] != "") and (candidate[:senate_class] != "I")
  #   puts "[#{entity_id}] Skipping senator, not up for election"
  #   return nil
  # end

  # if candidate[:seat_status] == ""
  #   puts "[#{entity_id}] Skipping, not up for election"
  #   return nil
  # end


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

# match name against ballotpedia data
def ballotpedia_name_for(name, chamber, state, district)
  lastname = name.split(" ")[-2]
  if lastname =~ /^Jr\.?/i
    lastname = name.split(" ")[-3]
  end

  if chamber == "house"
    candidates = bp_house[state][district]
  else
    candidates = bp_senate[state]
  end

  unless candidates
    puts "[#{chamber}][#{state}][#{district}](#{name}) No district found"
    exit
  end

  matches = candidates.select {|candidate| candidate['candidate'] =~ /#{lastname}/i}
  if matches.size > 1
    puts "Whoa, multiple matches: #{name} #{chamber} #{state} #{district}"
    exit
  elsif matches.size < 1
    puts "[#{name}][#{chamber}][#{state}][#{district}] No match for #{lastname}, skipping" if options[:skips]
    nil
  else
    if !["D", "R", "I"].include?(matches.first['party'])
      puts "[#{name}][#{chamber}][#{state}][#{district}] Not doing third parties for #{lastname}, skipping" if options[:skips]
    end

    # puts "[#{name}][#{chamber}][#{state}][#{district}] MATCHED #{lastname}"
    matches.first['candidate']
  end
end

# get filename from thumbs directory
def photo_filename_for(ballotpedia_name, chamber, state, district)
  lastname = ballotpedia_name.split(" ")[-1]
  if lastname =~ /^Jr\.?/i
    lastname = ballotpedia_name.split(" ")[-2]
  end

  # filename = ballotpedia_name.tr " ", "_"
  place = (chamber == "house") ? [state, district].join("-") : state
  files = Dir.glob("thumbs/#{chamber}_images_ac/#{place}/*").map {|p| File.basename p}
  matches = files.select {|f| f =~ /#{lastname}/i}
  if matches.size != 1
    puts "[#{ballotpedia_name}](#{lastname}) NO PHOTO - #{place} (#{chamber}) - #{files}"
    # exit
  end

  matches.first
end

def lastname_for(name)
  
  lastname
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