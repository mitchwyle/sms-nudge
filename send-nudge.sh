#!/bin/bash

# --- Configuration (Using CamelCase & Dashes) ---
BaseDir="$HOME/src/sms-nudge"
ApiKey=$(cat "$BaseDir/gemini-api-key.txt")
HistoryFile="$BaseDir/message-history.log"
# Recipient="4254696304@msg.fi.google.com" # Papa phone
Recipient="4257538486@msg.fi.google.com"   # Eitana phone
ModelName="gemini-2.5-flash"

# Your SMTP function (keeping it inside for portability)
sm() {
    # Using the raw password variable you set up
    SMTP2GOPSWD="aDi8v17HCx0VV5mK"
    
    input=$(cat)
    # Extract raw email for the envelope from the To/From headers
    to=$(echo "$input" | grep -i "^To:" | sed 's/[Tt][Oo]: //')
    from=$(echo "$input" | grep -i "^From:" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')

    curl --url 'smtp://smtp.smtp2go.com:587' \
         --ssl-reqd \
         --mail-from "$from" \
         --mail-rcpt "$to" \
         --upload-file <(echo "$input") \
         --user "mfw@wyle.org:$SMTP2GOPSWD" \
         --silent
}

# --- Context Recovery ---
# Grab the last 10 nudges to ensure uniqueness
PreviousMessages=$(tail -n 10 "$HistoryFile" | sed 's/"/\\"/g' | tr '\n' ' ')

# --- API Call ---
Prompt="Role: Witty personal assistant. Task: SMS reminder. Content: 'You need to wake up in 12 hours for work.' Context: Avoid repeating these recent messages: [$PreviousMessages]. Style: Short, varied, no hashtags, max 160 chars."

Response=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1/models/${ModelName}:generateContent?key=${ApiKey}" \
    -H 'Content-Type: application/json' \
    -d "{ \"contents\": [{\"parts\":[{\"text\": \"$Prompt\"}]}] }")

# Extract and clean
NewNudge=$(echo "$Response" | jq -r '.candidates[0].content.parts[0].text' | tr -d '\n' | sed 's/[#*"]//g')

# --- Validation & Execution ---
if [[ -n "$NewNudge" && "$NewNudge" != "null" ]]; then
    # Send using the format that passed the 'bone dry' test
    {
      echo "To: $Recipient"
      echo "From: mfw@wyle.org"
      echo "Subject: Daily Nudge"
      echo ""
      echo "$NewNudge"
    } | sm

    # Log the successful run
    echo "$(date '+%Y-%m-%d %H:%M'): $NewNudge" >> "$HistoryFile"
    echo "Success: $NewNudge"
else
    echo "Error: Gemini failed to generate a message."
    exit 1
fi
