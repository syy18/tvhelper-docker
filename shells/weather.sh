#!/bin/sh
# POSIX-compatible script to show Shanghai current weather and next-24h rain probability via Open-Meteo
# Defaults can be overridden via env vars LAT, LON, TZ or flags: -lat <val> -lon <val> -tz <val>

# defaults
LAT=${LAT:-31.2304}
LON=${LON:-121.4737}
TZ_PARAM=${TZ:-Asia/Shanghai}

usage() {
  cat <<EOF
Usage: $0 [-lat <latitude>] [-lon <longitude>] [-tz <timezone>]

Defaults:
  LAT=${LAT}
  LON=${LON}
  TZ=${TZ_PARAM}
Examples:
  $0
  LAT=31.2 LON=121.47 $0
  $0 -lat 31.2304 -lon 121.4737 -tz Asia/Shanghai
EOF
}

# simple arg parsing
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -lat)
      [ $# -ge 2 ] || { echo "Error: -lat requires a value" >&2; exit 2; }
      LAT=$2; shift 2 ;;
    -lon)
      [ $# -ge 2 ] || { echo "Error: -lon requires a value" >&2; exit 2; }
      LON=$2; shift 2 ;;
    -tz)
      [ $# -ge 2 ] || { echo "Error: -tz requires a value" >&2; exit 2; }
      TZ_PARAM=$2; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# requirements
command -v curl >/dev/null 2>&1 || { echo "Error: curl not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq not found (please install jq)" >&2; exit 1; }

# URL encode only the slash in timezone to keep POSIX sh simple
encode_tz=$(printf %s "$TZ_PARAM" | sed 's#/#%2F#g')

BASE_URL="https://api.open-meteo.com/v1/forecast"
PARAMS="latitude=${LAT}&longitude=${LON}&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,wind_speed_10m&hourly=precipitation_probability&timezone=${encode_tz}&forecast_days=2"

# fetch
resp=$(curl -fsS "${BASE_URL}?${PARAMS}") || { echo "Error: failed to query Open-Meteo API" >&2; exit 1; }

# parse and pretty print with jq
out=$(printf '%s' "$resp" | jq -r '
  if (.current? // null) and (.hourly? // null) and (.hourly.time? // null) and (.hourly.precipitation_probability? // null) then
    (.current.time // empty) as $ct |
    (.current.temperature_2m // empty) as $temp |
    (.current.apparent_temperature // empty) as $feels |
    (.current.relative_humidity_2m // empty) as $rh |
    (.current.wind_speed_10m // empty) as $wind |
    (.current.precipitation // empty) as $precip |
    # build hourly list with time and prob, defaulting null probs to 0
    ([ range(0; (.hourly.time | length)) as $i | {time: .hourly.time[$i], prob: ((.hourly.precipitation_probability[$i] // 0) // 0)} ]) as $items |
    ($items | map(select(.time >= $ct)) | .[:24]) as $next |
    (if ($next|length) > 0 then ($next | map(.prob) | max) else null end) as $maxp |
    ($next | map(select(.prob >= 50)) | first | .time // empty) as $next50time |
    if ($ct|type) != "string" or ($temp|type) == "null" then
      "__MISSING__"
    else
      ([ "Local time: " + $ct,
         "Temperature: " + ($temp|tostring) + "°C (feels " + ($feels|tostring) + "°C)",
         "Humidity: " + ($rh|tostring) + "%  Wind: " + ($wind|tostring) + " km/h",
         "Precipitation: " + ($precip|tostring) + " mm",
         "Max precip probability next 24h: " + (if $maxp then ($maxp|tostring) else "N/A" end) + "%"
       ] + (if $next50time then ["Next hour ≥50%: " + $next50time] else [] end)) | .[]
    end
  else
    "__MISSING__"
  end
')

if [ "$out" = "__MISSING__" ] || [ -z "$out" ]; then
  echo "Error: missing expected fields in API response" >&2
  exit 1
fi

echo "$out"
exit 0
