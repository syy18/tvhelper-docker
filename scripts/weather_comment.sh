#!/bin/bash

# Weather comment helper script for GitHub Actions
# This script processes weather requests and generates formatted replies

set -e

# Extract argument from comment body
comment_body="$1"
arg=$(echo "$comment_body" | sed 's/^\/weather[[:space:]]*//' | tr -d '\n\r')

# Default to Shanghai if no argument provided
if [ -z "$arg" ]; then
  arg="shanghai"
fi

echo "Extracted argument: $arg"

# Function to get coordinates from location name or return coordinates directly
get_coordinates() {
  local location="$1"
  
  # Check if argument looks like lat,lon coordinates
  if [[ "$location" =~ ^-?[0-9]+\.?[0-9]*,-?[0-9]+\.?[0-9]*$ ]]; then
    echo "Using coordinates directly: $location" >&2
    lat=$(echo "$location" | cut -d',' -f1)
    lon=$(echo "$location" | cut -d',' -f2)
    display_name="$location"
  else
    echo "Geocoding location: $location" >&2
    # URL encode the location name using printf to avoid newlines
    encoded_arg=$(printf "%s" "$location" | jq -sRr @uri)
    
    # Use Open-Meteo Geocoding API
    geocoding_url="https://geocoding-api.open-meteo.com/v1/search?name=${encoded_arg}&count=1&language=zh&format=json"
    echo "Geocoding URL: $geocoding_url" >&2
    
    geocoding_response=$(curl -s "$geocoding_url")
    echo "Geocoding response: $geocoding_response" >&2
    
    # Parse geocoding response
    if echo "$geocoding_response" | jq -e '.results | length > 0' > /dev/null; then
      lat=$(echo "$geocoding_response" | jq -r '.results[0].latitude')
      lon=$(echo "$geocoding_response" | jq -r '.results[0].longitude')
      display_name=$(echo "$geocoding_response" | jq -r '.results[0].name')
      country=$(echo "$geocoding_response" | jq -r '.results[0].country')
      if [ "$country" != "null" ] && [ "$country" != "" ]; then
        display_name="$display_name, $country"
      fi
    else
      echo "Geocoding failed, falling back to Shanghai" >&2
      lat="31.2304"
      lon="121.4737"
      display_name="上海, 中国"
    fi
  fi
  
  echo "$lat|$lon|$display_name"
}

# Function to get weather data and format reply
get_weather_reply() {
  local lat="$1"
  local lon="$2"
  local display_name="$3"
  
  # Get weather data from Open-Meteo API
  weather_url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,wind_speed_10m&hourly=precipitation_probability&timezone=auto"
  echo "Weather URL: $weather_url" >&2
  
  weather_response=$(curl -s "$weather_url")
  echo "Weather response: $weather_response" >&2
  
  # Parse current weather
  current_time=$(echo "$weather_response" | jq -r '.current.time')
  temp=$(echo "$weather_response" | jq -r '.current.temperature_2m')
  feels_like=$(echo "$weather_response" | jq -r '.current.apparent_temperature')
  humidity=$(echo "$weather_response" | jq -r '.current.relative_humidity_2m')
  precipitation=$(echo "$weather_response" | jq -r '.current.precipitation')
  wind_speed=$(echo "$weather_response" | jq -r '.current.wind_speed_10m')
  
  # Parse precipitation probability for next 24 hours
  precip_probabilities=$(echo "$weather_response" | jq -r '.hourly.precipitation_probability[0:24]')
  max_precip_prob=$(echo "$precip_probabilities" | jq 'max')
  
  # Find next hour with >=50% precipitation probability
  next_rain_hour=$(echo "$weather_response" | jq -r --argjson max_prob "$max_precip_prob" '
    if $max_prob >= 50 then
      .hourly as $hourly |
      .hourly.time[0:24] as $times |
      ($hourly.precipitation_probability[0:24] | to_entries | map(select(.value >= 50))[0].key) as $index |
      $times[$index]
    else
      null
    end
  ')
  
  # Format current time
  formatted_time=$(date -d "$current_time" "+%Y年%m月%d日 %H:%M" 2>/dev/null || echo "$current_time")
  
  # Format next rain hour if exists
  if [ "$next_rain_hour" != "null" ] && [ "$next_rain_hour" != "" ]; then
    formatted_rain_hour=$(date -d "$next_rain_hour" "%m月%d日 %H:%M" 2>/dev/null || echo "$next_rain_hour")
    rain_info="下一个≥50%降雨概率时段: $formatted_rain_hour"
  else
    rain_info="未来24小时内无明显降雨时段"
  fi
  
  # Create markdown reply in Chinese
  reply_body="## 🌤️ 天气信息

**📍 位置**: $display_name ($lat, $lon)

**🕐 当前时间**: $formatted_time

**🌡️ 温度**: ${temp}°C (体感 ${feels_like}°C)

**💧 湿度**: ${humidity}%

**🌧️ 当前降水**: ${precipitation}mm

**💨 风速**: ${wind_speed}m/s

**☔ 未来24小时最高降雨概率**: ${max_precip_prob}%

**🕐 $rain_info**

---
*数据来源: Open-Meteo API*"

  echo "$reply_body"
}

# Main execution
coords_result=$(get_coordinates "$arg")
lat=$(echo "$coords_result" | cut -d'|' -f1)
lon=$(echo "$coords_result" | cut -d'|' -f2)
display_name=$(echo "$coords_result" | cut -d'|' -f3)

echo "LATITUDE=$lat"
echo "LONGITUDE=$lon"
echo "DISPLAY_NAME=$display_name"

# Generate weather reply
weather_reply=$(get_weather_reply "$lat" "$lon" "$display_name")
echo "WEATHER_REPLY=$weather_reply"

# Output for GitHub Actions environment (only if running in GitHub Actions)
if [ -n "$GITHUB_OUTPUT" ]; then
  echo "LATITUDE=$lat" >> $GITHUB_OUTPUT
  echo "LONGITUDE=$lon" >> $GITHUB_OUTPUT
  echo "DISPLAY_NAME=$display_name" >> $GITHUB_OUTPUT
  echo "WEATHER_REPLY<<EOF" >> $GITHUB_OUTPUT
  echo "$weather_reply" >> $GITHUB_OUTPUT
  echo "EOF" >> $GITHUB_OUTPUT
fi