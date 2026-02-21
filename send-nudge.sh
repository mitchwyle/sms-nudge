#!/bin/bash

# --- Configuration ---
BaseDir="$HOME/src/sms-nudge"
ApiKey=$(cat "$BaseDir/gemini-api-key.txt")
HistoryFile="$BaseDir/message-history.log"
Recipient="4254696304@msg.fi.google.com"
Model="gemini-2.5-flash"


########################

sm() {
  export SMTP2GOUSER="mfw@wyle.org"
  export SMTP2GOPSWD="aDi8v17HCx0VV5mK"
  export SMTP2GO="api-13880441DB0C43A2A494F43E8958D0E2"
  parse_headers() {
    awk -v FS='\n' '
        BEGIN { to=""; from=""; subject="" }
        /^[Tt][Oo]:/ { to=$0; sub(/^[Tt][Oo]:[ \t]*/, "", to) }
        /^[Ff][Rr][Oo][Mm]:/ { from=$0; sub(/^[Ff][Rr][Oo][Mm]:[ \t]*/, "", from) }
        /^[Ss][Uu][Bb][Jj][Ee][Cc][Tt]:/ { subject=$0; sub(/^[Ss][Uu][Bb][Jj][Ee][Cc][Tt]:[ \t]*/, "", subject) }
        /^$/ { nextfile }
        END { print to; print from; print subject }
    '
  }

  # Read input and parse headers
  input=$(cat | sed '/^\.$/d')
  readarray -t headers < <(echo "$input" | parse_headers)
  to="${headers[0]}"
  from="${headers[1]}"
  subject="${headers[2]}"

  # Validate headers
  if [ -z "$to" ] || [ -z "$from" ] || [ -z "$subject" ]; then
      echo "Error: Missing To, From, or Subject header" >&2
      echo ""
      exit 1
  fi
  if [ -z "$SMTP2GOPSWD" ]; then
      echo "Error: SMTP2GO SMTP password not set in \$SMTP2GOPSWD" >&2
      echo ""
      exit 1
  fi


  # DEBUG: Remove --silent to see the SMTP conversation
  # We use --mail-from with the RAW email only (no brackets or names)
  raw_from=$(echo "$from" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')

  curl --url 'smtp://smtp.smtp2go.com:587' \
       --ssl-reqd \
       --mail-from "$raw_from" \
       --mail-rcpt "$to" \
       --upload-file <(echo "$input") \
       --user "mfw@wyle.org:$SMTP2GOPSWD" \
       -v  # Use -v for this test to see if it says "250 OK"
       # --silent
}




########################

# --- Context Recovery ---
# Get last 10 messages for 'uniqueness' memory, escaped for JSON
PreviousMessages=$(tail -n 10 "$HistoryFile" | sed 's/"/\\"/g' | tr '\n' ' ')

# --- API Call ---
Prompt="Role: Friendly assistant. Task: SMS reminder. Content: 'Wake up in 12h for work.' Avoid these: [$PreviousMessages]. Max 160 chars. No markdown."

Response=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1/models/${Model}:generateContent?key=${ApiKey}" \
    -H 'Content-Type: application/json' \
    -d "{ \"contents\": [{\"parts\":[{\"text\": \"$Prompt\"}]}] }")

# Extract and clean message
NewNudge=$(echo "$Response" | jq -r '.candidates[0].content.parts[0].text' | tr -d '\n' | sed 's/[#*"]//g')

# --- Validation & Execution ---
if [[ -n "$NewNudge" && "$NewNudge" != "null" ]]; then
    # Send via mail command
    {
      echo "To: $Recipient"
      echo 'From: Papa <mfw@wyle.org>'
      echo "Subject: nudge test"
      echo ""
      echo $NewNudge
    } | sm
    
    # Update History for next time
    echo "$(date '+%Y-%m-%d %H:%M'): $NewNudge" >> "$HistoryFile"
    echo "Sent: $NewNudge"
else
    echo "Error: Gemini response was empty. Check API/Network."
    exit 1
fi
