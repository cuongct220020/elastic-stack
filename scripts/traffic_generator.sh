#!/usr/bin/env bash
# traffic_generator.sh
# Simulates 1000 users interacting with the Document API via Nginx HTTPS.
# Generates Audit Logs for Elastic Stack analysis.

# Use HTTPS port 443 (Nginx) instead of plain HTTP
API_URL="https://localhost:443/documents"
TOTAL_USERS=1000
DOC_IDS=()

echo "--- PHASE 1: Seeding Initial Data via HTTPS ---"
for i in {1..20}
do
    USER_ID="user_$((RANDOM % TOTAL_USERS + 1))"
    echo "User $USER_ID is creating a document..."
    
    # -k: insecure (allow self-signed certs)
    # Removing -s (silent) temporarily from the output capture to catch errors if any
    RESPONSE=$(curl -sk -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{\"owner_id\": \"$USER_ID\", \"title\": \"Seed Document $i\", \"content\": \"Content for document $i\"}")
    
    # Extract ID from response (matching either "id" or "_id")
    NEW_ID=$(echo "$RESPONSE" | grep -o '"_\{0,1\}id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$NEW_ID" ]; then
        DOC_IDS+=("$NEW_ID")
    else
        echo "  -> FAILED to create document. API Response was:"
        echo "  -> $RESPONSE"
    fi
done

echo "--- PHASE 2: Chaos Mode (Infinite Loop) ---"
echo "Press [CTRL+C] to stop."

while true
do
    # 1. Select a random user from the 1000 users pool
    ACTOR_ID="user_$((RANDOM % TOTAL_USERS + 1))"
    
    # 2. Select a random document from our list
    DOC_COUNT=${#DOC_IDS[@]}
    if [ $DOC_COUNT -eq 0 ]; then
        echo "Error: No documents available to interact with. Check API connection."
        exit 1
    fi
    RANDOM_DOC_ID=${DOC_IDS[$((RANDOM % DOC_COUNT))]}
    
    # 3. Select a random action (1-4)
    ACTION=$((RANDOM % 4 + 1))
    
    case $ACTION in
        1)
            echo "Action: User $ACTOR_ID is LISTING all documents."
            curl -sk -X GET "$API_URL?user_id=$ACTOR_ID" > /dev/null
            ;;
        2)
            echo "Action: User $ACTOR_ID is READING document $RANDOM_DOC_ID."
            curl -sk -X GET "$API_URL/$RANDOM_DOC_ID?user_id=$ACTOR_ID" > /dev/null
            ;;
        3)
            echo "Action: User $ACTOR_ID is UPDATING document $RANDOM_DOC_ID."
            curl -sk -X PUT "$API_URL/$RANDOM_DOC_ID" \
                -H "Content-Type: application/json" \
                -d "{\"user_id\": \"$ACTOR_ID\", \"title\": \"Updated by $ACTOR_ID\", \"content\": \"Malicious update!\"}" > /dev/null
            ;;
        4)
            echo "Action: User $ACTOR_ID is DELETING document $RANDOM_DOC_ID."
            curl -sk -X DELETE "$API_URL/$RANDOM_DOC_ID?user_id=$ACTOR_ID" > /dev/null
            ;;
    esac

    # Wait a bit between requests
    sleep 0.5
done