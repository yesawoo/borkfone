# nanp-prefixes

A SQLite database (and CSV) mapping North American phone number prefixes to cities, states/provinces, and geographic coordinates.

Given a phone number like `+1 (509) 216-1234`, look up that it's `Spokane, WA` at `47.66, -117.43` -- instantly, offline, with no API calls.

## What's in it

- **32,496** prefix entries covering the US, Canada, and Caribbean NANP regions
- **420** area codes (NPA) with state/province-level fallbacks
- **10,371** unique locations with **96.9%** coordinate coverage
- Coordinates from [GeoNames](https://www.geonames.org/) open data (CC BY 4.0)
- Prefix-to-location mappings from [Google's libphonenumber](https://github.com/google/libphonenumber) (Apache 2.0)

## Files

| File | Size | Description |
|------|------|-------------|
| `nanp_prefixes.db` | 4.2 MB | SQLite database (recommended) |
| `nanp_prefixes.csv` | 2.0 MB | CSV export of the same data |
| `data/nanp_geocoding.txt` | source | Prefix-to-location mappings |
| `data/nanp_coordinates.txt` | source | Location-to-coordinate mappings |

## Schema

```sql
CREATE TABLE prefixes (
    prefix    TEXT PRIMARY KEY,  -- e.g. "1509216" (country + NPA + NXX)
    npa       TEXT NOT NULL,     -- area code, e.g. "509"
    nxx       TEXT,              -- exchange, e.g. "216" (NULL for area-code-only entries)
    location  TEXT NOT NULL,     -- original location string, e.g. "Spokane, WA"
    city      TEXT,              -- parsed city name (NULL for state-only entries)
    state     TEXT,              -- 2-letter state/province abbreviation
    country   TEXT,              -- "US" or "CA" (NULL for Caribbean)
    latitude  REAL,             -- decimal degrees (NULL if unresolved)
    longitude REAL              -- decimal degrees (NULL if unresolved)
);
```

Indexes on `npa`, `state`, and `(city, state)`.

## Example queries

### Look up a phone number

The most common use case. Given a phone number, extract the 6-digit prefix (area code + exchange) and try that first, falling back to the 3-digit area code:

```sql
-- Phone number: +1 (212) 555-1234
-- Try NPA+NXX first ("1212555"), then fall back to NPA ("1212")
SELECT * FROM prefixes
WHERE prefix IN ('1212555', '1212')
ORDER BY length(prefix) DESC
LIMIT 1;

-- Result: New York, NY | 40.71427 | -74.00597
```

### Look up by area code + exchange (NPA-NXX)

```sql
SELECT city, state, country, latitude, longitude
FROM prefixes WHERE prefix = '1509216';

-- Spokane | WA | US | 47.65966 | -117.42908
```

### Fall back to area code only

When a specific exchange isn't in the database, the area code entry gives a state/province-level result:

```sql
SELECT location, latitude, longitude
FROM prefixes WHERE prefix = '1509';

-- Washington State | 47.6062 | -122.3321
```

### Find all prefixes for a city

```sql
SELECT prefix, npa, nxx
FROM prefixes
WHERE city = 'Portland' AND state = 'OR'
ORDER BY prefix;
```

### List all area codes in a state

```sql
SELECT DISTINCT npa
FROM prefixes
WHERE state = 'TX' AND nxx IS NULL
ORDER BY npa;

-- 210, 214, 254, 281, 325, 346, 361, 409, ...
```

### Canadian lookups

```sql
SELECT prefix, city, state, latitude, longitude
FROM prefixes
WHERE country = 'CA' AND city = 'Winnipeg';
```

### Find nearby prefixes (approximate distance)

Find prefixes within ~50km of a point using a bounding box and Euclidean approximation:

```sql
SELECT prefix, location, latitude, longitude,
  ROUND(
    111.045 * SQRT(
      POWER(latitude - 40.7128, 2) +
      POWER((longitude - (-74.006)) * COS(RADIANS(40.7128)), 2)
    ), 1
  ) AS distance_km
FROM prefixes
WHERE latitude BETWEEN 40.4 AND 41.0
  AND longitude BETWEEN -74.3 AND -73.7
  AND nxx IS NOT NULL
ORDER BY distance_km
LIMIT 10;
```

### Count prefixes by state

```sql
SELECT state, country, COUNT(*) as prefix_count
FROM prefixes
WHERE state IS NOT NULL
GROUP BY state, country
ORDER BY prefix_count DESC
LIMIT 10;
```

### Find prefixes missing coordinates

```sql
SELECT prefix, location
FROM prefixes
WHERE latitude IS NULL
ORDER BY prefix;
```

## Usage from code

### Ruby

```ruby
require "sqlite3"

db = SQLite3::Database.new("nanp_prefixes.db")
db.results_as_hash = true

phone = "+12125551234"
digits = phone.gsub(/\D/, "").sub(/^1/, "")
npa_nxx = "1#{digits[0, 6]}"
npa = "1#{digits[0, 3]}"

row = db.get_first_row(
  "SELECT * FROM prefixes WHERE prefix IN (?, ?) ORDER BY length(prefix) DESC LIMIT 1",
  [npa_nxx, npa]
)

puts "#{row['city']}, #{row['state']} (#{row['latitude']}, #{row['longitude']})"
# => New York, NY (40.71427, -74.00597)
```

### Python

```python
import sqlite3, re

db = sqlite3.connect("nanp_prefixes.db")
db.row_factory = sqlite3.Row

phone = "+12125551234"
digits = re.sub(r'\D', '', phone).lstrip('1') if len(re.sub(r'\D', '', phone)) == 11 else re.sub(r'\D', '', phone)
npa_nxx = f"1{digits[:6]}"
npa = f"1{digits[:3]}"

row = db.execute(
    "SELECT * FROM prefixes WHERE prefix IN (?, ?) ORDER BY length(prefix) DESC LIMIT 1",
    (npa_nxx, npa)
).fetchone()

print(f"{row['city']}, {row['state']} ({row['latitude']}, {row['longitude']})")
# => New York, NY (40.71427, -74.00597)
```

### JavaScript (Node.js with better-sqlite3)

```javascript
const Database = require('better-sqlite3');
const db = new Database('nanp_prefixes.db');

const phone = '+12125551234';
const digits = phone.replace(/\D/g, '').replace(/^1/, '');
const npaNxx = '1' + digits.slice(0, 6);
const npa = '1' + digits.slice(0, 3);

const row = db.prepare(
  'SELECT * FROM prefixes WHERE prefix IN (?, ?) ORDER BY length(prefix) DESC LIMIT 1'
).get(npaNxx, npa);

console.log(`${row.city}, ${row.state} (${row.latitude}, ${row.longitude})`);
// => New York, NY (40.71427, -74.00597)
```

## How it's built

The database merges two datasets:

1. **[libphonenumber geocoding data](https://github.com/google/libphonenumber)** maps NANP prefixes (NPA or NPA-NXX) to location names like "Spokane, WA"
2. **[GeoNames cities500](https://download.geonames.org/export/dump/)** provides coordinates for those locations (cities with population > 500)

The generation scripts match location names to coordinates using exact matches, abbreviation expansion (e.g. "Hts" to "Heights"), and fuzzy matching. State/province-only entries fall back to largest-city coordinates.

### Rebuilding

To regenerate the coordinates file (if the geocoding source is updated):

```bash
# Download GeoNames data
curl -sL https://download.geonames.org/export/dump/cities500.zip -o "$TMPDIR/cities500.zip"
unzip -o "$TMPDIR/cities500.zip" -d "$TMPDIR"
curl -sL https://download.geonames.org/export/dump/admin1CodesASCII.txt -o "$TMPDIR/admin1CodesASCII.txt"

# Regenerate coordinates
ruby script/generate_coordinates.rb

# Rebuild the database and CSV
ruby script/build_db.rb
```

## Data sources and licensing

- **Prefix-to-location mappings**: [Google libphonenumber](https://github.com/google/libphonenumber), Apache License 2.0
- **Coordinates**: [GeoNames](https://www.geonames.org/), Creative Commons Attribution 4.0

This project's code is released under the MIT License.
