#!/bin/bash
CRON_FILE="cronc.txt"

# Define Cronicle API details
CRONICLE_URL="http://xxxxxxxxxxxxx:3012/api/app"
#API_TOKEN="0a987fc2ceb738be80406979dc3c2605"
API_TOKEN="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
TARGET="maingrp"
NOTIFICATION_EMAIL_FAILURE="purnasai.g@cartrade.com,sro0618346@gmail.com"

FAILED_EVENTS=()

# Function to extract event name
extract_event_name() {
    local command="$1"
    local event_name=$(echo "$command" | grep -oP '(?<=--output-document=)[^ ]+' | xargs basename | sed 's/\.html//')

    if [[ -z "$event_name" ]]; then
        event_name=$(echo "$command" | grep -oP '[^/]+\.php' | sed 's/\.php//')
    fi

    echo "$event_name"
}

# Function to extract PHP URL
extract_php_url() {
    local command="$1"
    local php_url=$(echo "$command" | grep -oP 'http[^ ]+\.php(\?[^ ]*)?')
    echo "$php_url"
}

# Function to convert cron expression to Cronicle timing format
convert_cron_to_timing() {
    local cron_expr="$1"
    local minutes=() hours=() days=() months=() weekdays=()

    IFS=' ' read -r minute hour day month weekday <<< "$cron_expr"

    expand_cron_field() {
        local field="$1"
        local max="$2"
        local result=()

        if [[ "$field" == "*" ]]; then
            echo "[]"
            return
        elif [[ "$field" =~ \*/([0-9]+) ]]; then
            local step="${BASH_REMATCH[1]}"
            for ((i=0; i<=max; i+=step)); do
                result+=("$i")
            done
        else
            IFS=',' read -ra parts <<< "$field"
            for part in "${parts[@]}"; do
                if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    for ((i=${BASH_REMATCH[1]}; i<=${BASH_REMATCH[2]}; i++)); do
                        result+=("$i")
                    done
                else
                    result+=("$((10#$part))")  # ✅ Removes leading zero
                fi
            done
        fi

        echo "[${result[*]}]" | sed 's/ /,/g'
    }

    minutes=$(expand_cron_field "$minute" 59)
    hours=$(expand_cron_field "$hour" 23)
    months=$(expand_cron_field "$month" 12)
#    weekdays=$(expand_cron_field "$weekday" 6)
declare -A WEEKDAYS_MAP=( ["sun"]=0 ["mon"]=1 ["tue"]=2 ["wed"]=3 ["thu"]=4 ["fri"]=5 ["sat"]=6 )

convert_weekday_names() {
    local input="$1"
    local result=()

    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        if [[ "${WEEKDAYS_MAP[$part]}" ]]; then
            result+=("${WEEKDAYS_MAP[$part]}")
        else
            result+=("$part")  # Keep numeric values as-is
        fi
    done

    echo "[${result[*]}]" | sed 's/ /,/g'
}

weekdays=$(convert_weekday_names "$weekday")

    # ✅ FIX: Convert "day" correctly and rename "month_days" to "days"
    if [[ "$day" != "*" ]]; then
        days=$(expand_cron_field "$day" 31)
    else
        days="[]"
    fi

    JSON="{"
    [[ "$minutes" != "[]" ]] && JSON+="\"minutes\": $minutes,"
    [[ "$hours" != "[]" ]] && JSON+="\"hours\": $hours,"
    [[ "$days" != "[]" ]] && JSON+="\"days\": $days,"
    [[ "$months" != "[]" && "$month" != "*" ]] && JSON+="\"months\": $months,"
    [[ "$weekdays" != "[]" && "$weekday" != "*" ]] && JSON+="\"weekdays\": $weekdays,"
    JSON="${JSON%,}}"

    echo "$JSON"
}

# Function to update the event if needed
update_event_if_needed() {
    local event_id="$1"
    local updated_json="$2"

    echo "🔄 Updating event ID: $event_id to fix missing 'days' field..."
    RESPONSE=$(curl -s -X POST "$CRONICLE_URL/update_event" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_TOKEN" \
        -d "$updated_json")

    echo "📌 Update Response: $RESPONSE"

    if echo "$RESPONSE" | grep -q '"code":0'; then
        echo "✅ Successfully updated event: $event_id"
    else
        echo "❌ Failed to update event: $event_id"
    fi
}

# Process cronc.txt
while IFS= read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

    CRON_SCHEDULE=$(echo "$line" | awk '{print $1,$2,$3,$4,$5}')
    COMMAND=$(echo "$line" | awk '{$1=$2=$3=$4=$5=""; print substr($0,2)}')

    EVENT_NAME=$(extract_event_name "$COMMAND")
    PHP_URL=$(extract_php_url "$COMMAND")

    echo "🔍 Extracted Event Name: $EVENT_NAME"
    echo "🔍 Extracted PHP URL: $PHP_URL"
    echo "🔍 Cron Schedule: $CRON_SCHEDULE"

    [[ -z "$EVENT_NAME" || -z "$PHP_URL" ]] && continue

    TIMING_JSON=$(convert_cron_to_timing "$CRON_SCHEDULE")

    echo "🔍 Timing JSON for $EVENT_NAME: $TIMING_JSON"

    SCRIPT_FILE="/opt/cronicle_scripts/${EVENT_NAME}.sh"
    mkdir -p /opt/cronicle_scripts

    cat > "$SCRIPT_FILE" <<EOF
#!/bin/sh

# ${EVENT_NAME} script
pwd
rm -f ${EVENT_NAME}.txt
curl -i "$PHP_URL" -o ${EVENT_NAME}.txt
ls -l
cat ${EVENT_NAME}.txt
grep 'HTTP/1.1 200' ${EVENT_NAME}.txt
EOF

    chmod +x "$SCRIPT_FILE"
    echo "✅ Shell script created: $SCRIPT_FILE"

    SCRIPT_CONTENT=$(jq -Rs . < "$SCRIPT_FILE")

    JSON_PAYLOAD=$(cat <<EOF
{
    "title": "$EVENT_NAME",
    "category": "xxxxxxxxxxxx",
    "plugin": "shellplug",
    "target": "$TARGET",
    "enabled": true,
    "timing": $TIMING_JSON,
    "params": {
        "script": $SCRIPT_CONTENT
    },
    "notify_fail": "$NOTIFICATION_EMAIL_FAILURE"
}
EOF
)

    echo "📌 JSON Payload for $EVENT_NAME:"
    echo "$JSON_PAYLOAD" | jq .

    RESPONSE=$(curl -s -X POST "$CRONICLE_URL/create_event" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_TOKEN" \
        -d "$JSON_PAYLOAD")

    echo "📌 API Response: $RESPONSE"

    if echo "$RESPONSE" | grep -q '"code":0'; then
        echo "✅ Created event: $EVENT_NAME"
    else
        echo "❌ Failed to create event: $EVENT_NAME"
        echo "🔴 Full Error Response: $RESPONSE"
        FAILED_EVENTS+=("$EVENT_NAME")
    fi

done < "$CRON_FILE"

if [[ ${#FAILED_EVENTS[@]} -gt 0 ]]; then
    echo -e "\n❌ The following events failed to create:"
    for event in "${FAILED_EVENTS[@]}"; do
        echo "  - $event"
    done
else
    echo -e "\n✅ All events created successfully!"
fi
