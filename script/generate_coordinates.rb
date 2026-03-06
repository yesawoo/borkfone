#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates data/nanp_coordinates.txt by matching NANP location names
# against the GeoNames cities500 dataset. No API keys needed.
#
# Prerequisites (downloaded to $TMPDIR):
#   cities500.txt        - from https://download.geonames.org/export/dump/cities500.zip
#   admin1CodesASCII.txt - from https://download.geonames.org/export/dump/admin1CodesASCII.txt
#
# Download them:
#   curl -sL https://download.geonames.org/export/dump/cities500.zip -o "$TMPDIR/cities500.zip"
#   unzip -o "$TMPDIR/cities500.zip" -d "$TMPDIR"
#   curl -sL https://download.geonames.org/export/dump/admin1CodesASCII.txt -o "$TMPDIR/admin1CodesASCII.txt"
#
# Usage: ruby script/generate_coordinates.rb

TMPDIR = ENV.fetch("TMPDIR", "/tmp")
CITIES_FILE = File.join(TMPDIR, "cities500.txt")
ADMIN_FILE = File.join(TMPDIR, "admin1CodesASCII.txt")
ROOT = File.expand_path("..", __dir__)
NANP_FILE = File.join(ROOT, "data", "nanp_geocoding.txt")
OUTPUT_FILE = File.join(ROOT, "data", "nanp_coordinates.txt")

US_STATE_VARIATIONS = {
  "Alabama" => "AL", "Alaska" => "AK", "Arizona" => "AZ", "Arkansas" => "AR",
  "California" => "CA", "Colorado" => "CO", "Connecticut" => "CT", "Delaware" => "DE",
  "Florida" => "FL", "Georgia" => "GA", "Hawaii" => "HI", "Idaho" => "ID",
  "Illinois" => "IL", "Indiana" => "IN", "Iowa" => "IA", "Kansas" => "KS",
  "Kentucky" => "KY", "Louisiana" => "LA", "Maine" => "ME", "Maryland" => "MD",
  "Massachusetts" => "MA", "Michigan" => "MI", "Minnesota" => "MN", "Mississippi" => "MS",
  "Missouri" => "MO", "Montana" => "MT", "Nebraska" => "NE", "Nevada" => "NV",
  "New Hampshire" => "NH", "New Jersey" => "NJ", "New Mexico" => "NM", "New York" => "NY",
  "North Carolina" => "NC", "North Dakota" => "ND", "Ohio" => "OH", "Oklahoma" => "OK",
  "Oregon" => "OR", "Pennsylvania" => "PA", "Rhode Island" => "RI", "South Carolina" => "SC",
  "South Dakota" => "SD", "Tennessee" => "TN", "Texas" => "TX", "Utah" => "UT",
  "Vermont" => "VT", "Virginia" => "VA", "Washington" => "WA",
  "West Virginia" => "WV", "Wisconsin" => "WI", "Wyoming" => "WY",
  "Washington State" => "WA", "District of Columbia" => "DC", "Washington D.C." => "DC"
}.freeze

CA_PROVINCE_NAMES = {
  "Alberta" => "AB", "British Columbia" => "BC", "British Colombia" => "BC",
  "Manitoba" => "MB", "New Brunswick" => "NB", "Newfoundland and Labrador" => "NL",
  "Newfoundland" => "NL", "Northwest Territories" => "NT", "Nova Scotia" => "NS",
  "Nunavut" => "NU", "Ontario" => "ON", "Prince Edward Island" => "PE",
  "Quebec" => "QC", "Saskatchewan" => "SK", "Yukon" => "YT"
}.freeze

CA_ADMIN1 = {
  "AB" => "01", "BC" => "02", "MB" => "03", "NB" => "04", "NL" => "05",
  "NT" => "13", "NS" => "07", "NU" => "14", "ON" => "08", "PE" => "09",
  "QC" => "10", "SK" => "11", "YT" => "12"
}.freeze

CITY_ABBREVIATIONS = {
  "Hts" => "Heights", "Hgts" => "Heights", "Spgs" => "Springs",
  "Jct" => "Junction", "Pt" => "Point", "Ft" => "Fort", "Mt" => "Mount",
  "Pk" => "Park", "Bch" => "Beach", "Ctr" => "Center", "Twp" => "Township",
  "Vlg" => "Village", "Hbr" => "Harbor", "Lk" => "Lake", "Brg" => "Bridge",
  "Hl" => "Hill", "Hls" => "Hills", "Fls" => "Falls", "Spg" => "Spring",
  "Slphr" => "Sulphur", "Hse" => "House", "Crk" => "Creek",
  "Grn" => "Green", "Grv" => "Grove", "Vly" => "Valley",
  "Ste." => "Sainte", "St." => "Saint"
}.freeze

STATE_CAPITALS = {
  "AL" => [32.3668, -86.3000], "AK" => [64.2008, -149.4937],
  "AZ" => [33.4484, -112.0740], "AR" => [34.7465, -92.2896],
  "CA" => [37.7749, -122.4194], "CO" => [39.7392, -104.9903],
  "CT" => [41.7658, -72.6734], "DE" => [39.1582, -75.5244],
  "DC" => [38.9072, -77.0369], "FL" => [28.5383, -81.3792],
  "GA" => [33.7490, -84.3880], "HI" => [21.3069, -157.8583],
  "ID" => [43.6150, -116.2023], "IL" => [41.8781, -87.6298],
  "IN" => [39.7684, -86.1581], "IA" => [41.5868, -93.6250],
  "KS" => [39.0473, -95.6752], "KY" => [38.2009, -84.8733],
  "LA" => [29.9511, -90.0715], "ME" => [43.6591, -70.2568],
  "MD" => [39.2904, -76.6122], "MA" => [42.3601, -71.0589],
  "MI" => [42.3314, -83.0458], "MN" => [44.9778, -93.2650],
  "MS" => [32.2988, -90.1848], "MO" => [38.6270, -90.1994],
  "MT" => [46.8797, -110.3626], "NE" => [41.2565, -95.9345],
  "NV" => [36.1699, -115.1398], "NH" => [43.2081, -71.5376],
  "NJ" => [40.7357, -74.1724], "NM" => [35.0844, -106.6504],
  "NY" => [40.7128, -74.0060], "NC" => [35.2271, -80.8431],
  "ND" => [46.8772, -96.7898], "OH" => [39.9612, -82.9988],
  "OK" => [35.4676, -97.5164], "OR" => [45.5152, -122.6784],
  "PA" => [39.9526, -75.1652], "RI" => [41.8240, -71.4128],
  "SC" => [34.0007, -81.0348], "SD" => [43.5460, -96.7313],
  "TN" => [36.1627, -86.7816], "TX" => [30.2672, -97.7431],
  "UT" => [40.7608, -111.8910], "VT" => [44.4759, -73.2121],
  "VA" => [37.5407, -77.4360], "WA" => [47.6062, -122.3321],
  "WV" => [38.3498, -81.6326], "WI" => [43.0389, -87.9065],
  "WY" => [41.1400, -104.8202],
  "AB" => [51.0447, -114.0719], "BC" => [49.2827, -123.1207],
  "MB" => [49.8951, -97.1384], "NB" => [45.9636, -66.6431],
  "NL" => [47.5615, -52.7126], "NS" => [44.6488, -63.5752],
  "NT" => [62.4540, -114.3718], "NU" => [63.7467, -68.5170],
  "ON" => [43.6532, -79.3832], "PE" => [46.2382, -63.1311],
  "QC" => [45.5017, -73.5673], "SK" => [52.1332, -106.6700],
  "YT" => [60.7212, -135.0568]
}.freeze

def load_cities
  cities = {}
  File.foreach(CITIES_FILE) do |line|
    fields = line.strip.split("\t")
    country = fields[8]
    next unless %w[US CA].include?(country)

    name = fields[1]
    asciiname = fields[2]
    alternatenames = fields[3]
    lat = fields[4].to_f
    lon = fields[5].to_f
    admin1 = fields[10]
    population = fields[14].to_i

    entry = { lat: lat, lon: lon, population: population }

    names = [name, asciiname]
    names += alternatenames.split(",") if alternatenames && !alternatenames.empty?
    names.map!(&:strip).uniq!

    names.each do |n|
      next if n.empty?
      key = "#{n.downcase}|#{country}|#{admin1}"
      if !cities[key] || population > cities[key][:population]
        cities[key] = entry
      end
    end
  end
  cities
end

def expand_abbreviations(city)
  expanded = city.dup
  CITY_ABBREVIATIONS.each do |abbr, full|
    expanded = expanded.gsub(/\b#{Regexp.escape(abbr)}\b/, full)
  end
  expanded
end

def strip_township(city)
  city.sub(/\s*(Charter\s+)?Township$/i, "").strip
end

def resolve_city_state(city, state_abbr, cities)
  if CA_ADMIN1[state_abbr]
    country = "CA"
    admin1 = CA_ADMIN1[state_abbr]
  elsif state_abbr.match?(/\A[A-Z]{2}\z/)
    country = "US"
    admin1 = state_abbr
  else
    return nil
  end

  key = "#{city.downcase}|#{country}|#{admin1}"
  entry = cities[key]
  return [entry[:lat], entry[:lon]] if entry

  expanded = expand_abbreviations(city)
  if expanded != city
    key = "#{expanded.downcase}|#{country}|#{admin1}"
    entry = cities[key]
    return [entry[:lat], entry[:lon]] if entry
  end

  stripped = strip_township(city)
  if stripped != city
    key = "#{stripped.downcase}|#{country}|#{admin1}"
    entry = cities[key]
    return [entry[:lat], entry[:lon]] if entry
  end

  key = "#{city.downcase} city|#{country}|#{admin1}"
  entry = cities[key]
  return [entry[:lat], entry[:lon]] if entry

  normalized = city.downcase.gsub(/[^a-z ]/, "")
  cities.each do |k, v|
    k_city, k_country, k_admin = k.split("|")
    next unless k_country == country && k_admin == admin1
    if k_city.gsub(/[^a-z ]/, "") == normalized
      return [v[:lat], v[:lon]]
    end
  end

  nil
end

def resolve_location(location_name, cities)
  if location_name.include?(",")
    city, state_abbr = location_name.split(",", 2).map(&:strip)
    return resolve_city_state(city, state_abbr, cities)
  end

  abbr = US_STATE_VARIATIONS[location_name] || CA_PROVINCE_NAMES[location_name]
  return STATE_CAPITALS[abbr] if abbr && STATE_CAPITALS[abbr]

  nil
end

# --- Main ---

unless File.exist?(CITIES_FILE)
  warn "Missing GeoNames data files in #{TMPDIR}."
  warn "Download them first:"
  warn "  curl -sL https://download.geonames.org/export/dump/cities500.zip -o \"$TMPDIR/cities500.zip\""
  warn "  unzip -o \"$TMPDIR/cities500.zip\" -d \"$TMPDIR\""
  warn "  curl -sL https://download.geonames.org/export/dump/admin1CodesASCII.txt -o \"$TMPDIR/admin1CodesASCII.txt\""
  exit 1
end

puts "Loading GeoNames cities..."
cities = load_cities
puts "  Loaded #{cities.size} name variants for US/CA cities"

puts "Loading NANP locations..."
nanp_locations = {}
File.foreach(NANP_FILE) do |line|
  line = line.strip
  next if line.empty? || line.start_with?("#")
  _prefix, location = line.split("|", 2)
  nanp_locations[location] = true if location
end

unique_locations = nanp_locations.keys.sort
puts "  Found #{unique_locations.size} unique locations"

puts "Resolving coordinates..."
results = {}
matched = 0
unmatched = []

unique_locations.each do |location|
  coords = resolve_location(location, cities)
  if coords
    results[location] = coords
    matched += 1
  else
    unmatched << location
  end
end

puts "  Matched: #{matched}/#{unique_locations.size} (#{(matched * 100.0 / unique_locations.size).round(1)}%)"
puts "  Unmatched: #{unmatched.size}"

if unmatched.any?
  puts "\n  Sample unmatched locations:"
  unmatched.first(20).each { |loc| puts "    - #{loc}" }
end

File.open(OUTPUT_FILE, "w") do |f|
  f.puts "# NANP location coordinates"
  f.puts "# Generated from GeoNames cities500 dataset"
  f.puts "# Format: location_name|latitude|longitude"
  f.puts "#"
  results.sort_by { |k, _| k }.each do |location, (lat, lon)|
    f.puts "#{location}|#{lat}|#{lon}"
  end
end

puts "\nWrote #{results.size} entries to #{OUTPUT_FILE}"
