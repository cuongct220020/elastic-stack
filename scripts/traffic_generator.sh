#!/usr/bin/env bash
# traffic_generator.sh
# Simulates 1000 users interacting with the Document API to generate Audit Logs.

API_URL="http://localhost:80/documents"
TOTAL_USERS=1000
DOC_IDS=()

echo "--- PHASE 1: Seeding Initial Data ---"
for i in {1..20}
do
    USER_ID="user_$((RANDOM % TOTAL_USERS + 1))"
    echo "User $USER_ID is creating a document..."
    
    RESPONSE=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{\"owner_id\": \"$USER_ID\", \"title\": \"Seed Document $i\", \"content\": \"Content for document $i\"}")
    
    # Extract ID from response (using simple grep/cut for portability)
    NEW_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"”]*"' | cut -d'"' -f4)
    if [ -n "$NEW_ID" ]; then
        DOC_IDS+=("$NEW_ID")
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
    RANDOM_DOC_ID=${DOC_IDS[$((RANDOM % DOC_COUNT))]}
    
    # 3. Select a random action (1-4)
    ACTION=$((RANDOM % 4 + 1))
    
    case $ACTION in
        1)
            echo "Action: User $ACTOR_ID is LISTING all documents."
            curl -s -X GET "$API_URL?user_id=$ACTOR_ID" > /dev/null
            ;;
        2)
            echo "Action: User $ACTOR_ID is READING document $RANDOM_DOC_ID."
            curl -s -X GET "$API_URL/$RANDOM_DOC_ID?user_id=$ACTOR_ID" > /dev/null
            ;;
        3)
            echo "Action: User $ACTOR_ID is UPDATING document $RANDOM_DOC_ID."
            curl -s -X PUT "$API_URL/$RANDOM_DOC_ID" \
                -H "Content-Type: application/json" \
                -d "{\"user_id\": \"$ACTOR_ID\", \"title\": \"Updated by $ACTOR_ID\", \"content\": \"Malicious update!\"}" > /dev/null
            ;;
        4)
            echo "Action: User $ACTOR_ID is DELETING document $RANDOM_DOC_ID."
            curl -s -X DELETE "$API_URL/$RANDOM_DOC_ID?user_id=$ACTOR_ID" > /dev/null
            ;;
    esac

    # Wait a bit between requests to keep the logs readable but continuous
    sleep 0.5
done
