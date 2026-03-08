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
        echo "All seed documents have been deleted! Restart the script to seed again."
        exit 0
    fi
    
    # Pick a random index
    RANDOM_INDEX=$((RANDOM % DOC_COUNT))
    RANDOM_DOC_ID=${DOC_IDS[$RANDOM_INDEX]}
    
    # 3. Select a random action (1-4)
    # Weighting: 40% Read, 30% List, 20% Update, 10% Delete
    RAND_VAL=$((RANDOM % 100))
    if [ $RAND_VAL -lt 40 ]; then ACTION=2; # Read
    elif [ $RAND_VAL -lt 70 ]; then ACTION=1; # List
    elif [ $RAND_VAL -lt 90 ]; then ACTION=3; # Update
    else ACTION=4; # Delete
    fi
    
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
            HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -X DELETE "$API_URL/$RANDOM_DOC_ID?user_id=$ACTOR_ID")
            
            # If deletion was successful (204 No Content), remove it from our active array
            if [ "$HTTP_STATUS" -eq 204 ]; then
                echo "  -> Document $RANDOM_DOC_ID successfully soft-deleted. Removing from active target list."
                unset 'DOC_IDS[RANDOM_INDEX]'
                # Rebuild array to fix sparse indices
                DOC_IDS=("${DOC_IDS[@]}")
            fi
            ;;
    esac

    # Wait a bit between requests to keep the logs readable but continuous
    sleep 0.8
done