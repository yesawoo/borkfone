#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the borkfone.db SQLite database and borkfone.csv
# from the source data files.
#
# Source data:
#   - nanp_geocoding.txt: Google libphonenumber NANP geocoding dataset
#     (prefix → location name)
#   - nanp_coordinates.txt: GeoNames-derived coordinates
#     (location name → lat/lon)
#
# Usage: ruby script/build_db.rb

require "sqlite3"
require "csv"

ROOT = File.expand_path("..", __dir__)
GEOCODING_FILE = File.join(ROOT, "data", "nanp_geocoding.txt")
COORDINATES_FILE = File.join(ROOT, "data", "nanp_coordinates.txt")
DB_FILE = File.join(ROOT, "borkfone.db")
CSV_FILE = File.join(ROOT, "borkfone.csv")

# Load coordinates: location_name → [lat, lon]
def load_coordinates
  coords = {}
  File.foreach(COORDINATES_FILE) do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    location, lat, lon = line.split("|", 3)
    coords[location] = [lat.to_f, lon.to_f] if location && lat && lon
  end
  coords
end

# Load geocoding: yields [prefix, location_name] pairs
def each_geocoding_entry
  File.foreach(GEOCODING_FILE) do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    prefix, location = line.split("|", 2)
    yield prefix, location if prefix && location
  end
end

# Parse "City, ST" into [city, state] or return [nil, location] for state-only
def parse_location(location)
  if location.include?(",")
    city, state = location.split(",", 2).map(&:strip)
    [city, state]
  else
    [nil, location]
  end
end

# Determine country from state/province abbreviation
US_STATES = %w[AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME
               MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI
               SC SD TN TX UT VT VA WA WV WI WY].freeze
CA_PROVINCES = %w[AB BC MB NB NL NS NT NU ON PE QC SK YT].freeze

STATE_NAMES_TO_ABBR = {
  "Alabama" => "AL", "Alaska" => "AK", "Arizona" => "AZ", "Arkansas" => "AR",
  "California" => "CA", "Colorado" => "CO", "Connecticut" => "CT", "Delaware" => "DE",
  "District of Columbia" => "DC", "Florida" => "FL", "Georgia" => "GA", "Hawaii" => "HI",
  "Idaho" => "ID", "Illinois" => "IL", "Indiana" => "IN", "Iowa" => "IA",
  "Kansas" => "KS", "Kentucky" => "KY", "Louisiana" => "LA", "Maine" => "ME",
  "Maryland" => "MD", "Massachusetts" => "MA", "Michigan" => "MI", "Minnesota" => "MN",
  "Mississippi" => "MS", "Missouri" => "MO", "Montana" => "MT", "Nebraska" => "NE",
  "Nevada" => "NV", "New Hampshire" => "NH", "New Jersey" => "NJ", "New Mexico" => "NM",
  "New York" => "NY", "North Carolina" => "NC", "North Dakota" => "ND", "Ohio" => "OH",
  "Oklahoma" => "OK", "Oregon" => "OR", "Pennsylvania" => "PA", "Rhode Island" => "RI",
  "South Carolina" => "SC", "South Dakota" => "SD", "Tennessee" => "TN", "Texas" => "TX",
  "Utah" => "UT", "Vermont" => "VT", "Virginia" => "VA", "Washington" => "WA",
  "Washington State" => "WA", "Washington D.C." => "DC",
  "West Virginia" => "WV", "Wisconsin" => "WI", "Wyoming" => "WY",
  "Alberta" => "AB", "British Columbia" => "BC", "British Colombia" => "BC",
  "Manitoba" => "MB", "New Brunswick" => "NB", "Newfoundland and Labrador" => "NL",
  "Newfoundland" => "NL", "Northwest Territories" => "NT", "Nova Scotia" => "NS",
  "Nunavut" => "NU", "Ontario" => "ON", "Prince Edward Island" => "PE",
  "Quebec" => "QC", "Saskatchewan" => "SK", "Yukon" => "YT"
}.freeze

def country_for(state_abbr)
  return "US" if US_STATES.include?(state_abbr)
  return "CA" if CA_PROVINCES.include?(state_abbr)
  nil
end

# --- Main ---

puts "Loading coordinates..."
coords = load_coordinates
puts "  #{coords.size} locations with coordinates"

puts "Building database..."
File.delete(DB_FILE) if File.exist?(DB_FILE)

db = SQLite3::Database.new(DB_FILE)

db.execute_batch(<<~SQL)
  CREATE TABLE prefixes (
    prefix TEXT PRIMARY KEY,
    npa TEXT NOT NULL,
    nxx TEXT,
    location TEXT NOT NULL,
    city TEXT,
    state TEXT,
    country TEXT,
    latitude REAL,
    longitude REAL
  );

  CREATE INDEX idx_prefixes_npa ON prefixes(npa);
  CREATE INDEX idx_prefixes_state ON prefixes(state);
  CREATE INDEX idx_prefixes_city_state ON prefixes(city, state);
SQL

insert = db.prepare(<<~SQL)
  INSERT OR REPLACE INTO prefixes
    (prefix, npa, nxx, location, city, state, country, latitude, longitude)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
SQL

csv = CSV.open(CSV_FILE, "w")
csv << %w[prefix npa nxx location city state country latitude longitude]

total = 0
with_coords = 0

db.transaction do
  each_geocoding_entry do |prefix, location|
    # prefix is like "1201" (area code) or "1201200" (area code + exchange)
    digits = prefix.sub(/^1/, "")
    npa = digits[0, 3]
    nxx = digits.length > 3 ? digits[3, 3] : nil

    city, state = parse_location(location)

    # For state-only entries, resolve the abbreviation
    if city.nil?
      abbr = STATE_NAMES_TO_ABBR[state]
      if abbr
        state = abbr
      end
    end

    country = country_for(state)
    lat, lon = coords[location]

    if lat
      with_coords += 1
    end

    insert.execute(prefix, npa, nxx, location, city, state, country, lat, lon)
    csv << [prefix, npa, nxx, location, city, state, country, lat, lon]
    total += 1
  end
end

insert.close
csv.close
db.close

puts "  #{total} prefix entries"
puts "  #{with_coords} with coordinates (#{(with_coords * 100.0 / total).round(1)}%)"
puts "\nWrote #{DB_FILE}"
puts "Wrote #{CSV_FILE}"
