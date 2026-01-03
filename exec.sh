#!/bin/bash

# Check if a date was provided
if [ -z "$1" ]; then
  echo "Error: No start date provided."
  echo "Usage: ./git_pattern_macos.sh YYYY-MM-DD"
  exit 1
fi

CURRENT_DATE="$1"

# --- CONFIGURATION ---

# Change this to "big-text.txt" if the file is in the same folder
FILE_PATH="./big-text.txt"

# --- FILE LOADING ---

if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File '$FILE_PATH' not found."
    exit 1
fi

if [ ! -w "$FILE_PATH" ]; then
    echo "Error: File '$FILE_PATH' is not writable. Check permissions."
    exit 1
fi

# Load file content into an array of words
WORDS=( $(cat "$FILE_PATH") )
TOTAL_WORDS=${#WORDS[@]}
WORD_IDX=0

echo "Starting git commit sequence from: $CURRENT_DATE"
echo "Loaded text from $FILE_PATH: $TOTAL_WORDS words."

if [ "$TOTAL_WORDS" -eq 0 ]; then
    echo "Error: The text file is empty."
    exit 1
fi

# --- HELPER FUNCTION FOR MACOS DATES ---
function add_days {
    local date_str=$1
    local days=$2
    # macOS specific date math
    date -j -v+"$days"d -f "%Y-%m-%d" "$date_str" +%Y-%m-%d
}

# --- PATTERN CONFIGURATION ---

PATTERN=(
  "fill 4" "skip 2" "fill 1" "skip 3" "fill 1" "skip 2"
  "fill 1" "skip 3" "fill 1" "skip 2" "fill 9" "skip 2"
  "fill 1" "skip 3" "fill 1" "skip 2" "fill 1" "skip 3"
  "fill 1" "skip 2" "fill 4"
)

# --- TRANSACTION SETUP ---

START_HASH=$(git rev-parse HEAD 2>/dev/null)

function rollback_and_exit {
    echo ""
    echo "CRITICAL ERROR: Ran out of words at index $WORD_IDX (File ended)!"
    echo "Initiating Git Rollback..."

    if [ -n "$START_HASH" ]; then
        git reset --hard "$START_HASH"
        echo "Reverted to commit: $START_HASH"
    else
        git update-ref -d HEAD
        rm -f .git/index
        echo "Reverted to empty repository state."
    fi

    echo "The text file '$FILE_PATH' was NOT modified."
    exit 1
}

# --- MAIN LOOP ---

for step in "${PATTERN[@]}"; do
  action=$(echo $step | cut -d' ' -f1)
  count=$(echo $step | cut -d' ' -f2)

  if [ "$action" == "fill" ]; then
    for ((i=1; i<=count; i++)); do

      # 1. CHECK FOR FAILURE
      if [ $WORD_IDX -ge $TOTAL_WORDS ]; then
        rollback_and_exit
      fi

      # 2. GENERATE MESSAGE
      COMMIT_MSG=""

      while true; do
        if [ $WORD_IDX -ge $TOTAL_WORDS ]; then
            break
        fi

        NEXT_WORD="${WORDS[$WORD_IDX]}"

        # Calculate potential length
        if [ -z "$COMMIT_MSG" ]; then
            POTENTIAL_LEN=${#NEXT_WORD}
        else
            POTENTIAL_LEN=$((${#COMMIT_MSG} + 1 + ${#NEXT_WORD}))
        fi

        # Check limit (50 chars)
        if [ $POTENTIAL_LEN -le 50 ]; then
            if [ -z "$COMMIT_MSG" ]; then
                COMMIT_MSG="$NEXT_WORD"
            else
                COMMIT_MSG="$COMMIT_MSG $NEXT_WORD"
            fi
            ((WORD_IDX++))
        else
            break
        fi
      done

      if [ -z "$COMMIT_MSG" ]; then
        rollback_and_exit
      fi

      # 3. EXECUTE COMMIT
      echo "[$CURRENT_DATE] Committing: '$COMMIT_MSG'"

      # We capture the output of git commit to check for errors
      if ! git commit --allow-empty --quiet --date "$CURRENT_DATE" -m "$COMMIT_MSG"; then
          echo "Error executing git commit. Aborting."
          rollback_and_exit
      fi

      # Increment date (macOS Syntax)
      CURRENT_DATE=$(add_days "$CURRENT_DATE" 1)
    done

  elif [ "$action" == "skip" ]; then
    echo "Skipping $count days..."
    # Increment date (macOS Syntax)
    CURRENT_DATE=$(add_days "$CURRENT_DATE" "$count")
  fi
done

# --- FINALIZATION & FILE UPDATE ---

echo ""
echo "Sequence finished successfully."
echo "Updating source file..."

REMAINING_WORDS=("${WORDS[@]:$WORD_IDX}")
echo "${REMAINING_WORDS[*]}" > "$FILE_PATH"

echo "File updated. Used $WORD_IDX words. Remaining words: ${#REMAINING_WORDS[@]}."