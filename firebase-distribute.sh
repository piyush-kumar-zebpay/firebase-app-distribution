#!/bin/bash
# ==============================================================================
# FIREBASE APP DISTRIBUTION SCRIPT
# ==============================================================================
# Description:
#   Interactive CLI tool to build and upload Android apps to Firebase App Distribution.
#
# Usage:
#   ./firebase-distribute.sh
#
# ==============================================================================

set -e  # Exit immediately if a command exits with a non-zero status

# ==============================================================================
# 1. CONFIGURATION & EDITABLE VARIABLES
# ==============================================================================
# Modify these paths and values to match your project structure

# Project Paths
APP_MODULE_DIR="app"
BUILD_GRADLE="${APP_MODULE_DIR}/build.gradle.kts"

# Default Options
DEFAULT_DESCRIPTION="No description provided"
DEFAULT_TESTER_GROUPS=("qa" "qa-team" "devs") # Default options for the group selector

# ==============================================================================
# 2. VISUAL STYLING
# ==============================================================================
# ANSI Color Codes
ORANGE='\033[38;5;208m'
WHITE='\033[97m'
DARK_GRAY='\033[90m'
RED='\033[31m'
RESET='\033[0m'
BOLD='\033[1m'

# Symbols & Icons
ICON_STAR='✦'
ICON_FILLED='●'
ICON_EMPTY='○'
ICON_CHECKBOX_ON='◆'
ICON_CHECKBOX_OFF='◇'
ICON_SUCCESS='✓'
ICON_ARROW='›'

# UI Helpers
show_banner() {
    echo ""
    echo -e "${WHITE}${BOLD}"
    echo "                                                                                                                                       "
    echo "             █████╗ ██████╗ ██████╗     ██████╗ ██╗███████╗████████╗██████╗ ██╗██████╗ ██╗   ██╗████████╗██╗ ██████╗ ███╗   ██╗        "
    echo "            ██╔══██╗██╔══██╗██╔══██╗    ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║██╔══██╗██║   ██║╚══██╔══╝██║██╔═══██╗████╗  ██║        "
    echo "            ███████║██████╔╝██████╔╝    ██║  ██║██║███████╗   ██║   ██████╔╝██║██████╔╝██║   ██║   ██║   ██║██║   ██║██╔██╗ ██║        "
    echo "            ██╔══██║██╔═══╝ ██╔═══╝     ██║  ██║██║╚════██║   ██║   ██╔══██╗██║██╔══██╗██║   ██║   ██║   ██║██║   ██║██║╚██╗██║        "
    echo "            ██║  ██║██║     ██║         ██████╔╝██║███████║   ██║   ██║  ██║██║██████╔╝╚██████╔╝   ██║   ██║╚██████╔╝██║ ╚████║        "
    echo "            ╚═╝  ╚═╝╚═╝     ╚═╝         ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝    ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝        "
    echo -e "${RESET}"
    echo ""
}

cleanup() {
    tput cnorm 2>/dev/null # Restore cursor on exit
}
trap cleanup EXIT



# ==============================================================================
# 3. HELPER FUNCTIONS (System, Git, Gradle)
# ==============================================================================

get_git_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
}

get_git_author() {
    git config user.name 2>/dev/null || echo "Unknown Author"
}




# ==============================================================================
# 4. INTERACTIVE COMPONENT LIBRARY
# ==============================================================================
# These functions handle the low-level inputs and drawing.
# You generally do not need to edit these unless changing the UI behavior.

read_key() {
    local key
    IFS= read -rsn1 key
    # Handle arrow keys (escape sequences)
    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 key
        case "$key" in
            '[A') echo "UP" ;; '[B') echo "DOWN" ;; '[C') echo "RIGHT" ;; '[D') echo "LEFT" ;;
            *) echo "ESC" ;;
        esac
    elif [[ "$key" == "" ]]; then echo "ENTER"
    elif [[ "$key" == " " ]]; then echo "SPACE"
    else echo "$key"
    fi
}

show_single_select_menu() {
    # Arguments: Title, PreviousInfo, Option1, Option2, ...
    local title="$1"
    local prev_info="$2"
    shift 2
    local options=("$@")
    local selected_index=0
    local options_count=${#options[@]}
    
    tput civis # Hide cursor
    while true; do
        clear
        show_banner
        [ -n "$prev_info" ] && { echo -e "$prev_info"; echo ""; }
        
        echo -e "  ${WHITE}$title${RESET}"
        echo -e "  ${DARK_GRAY}Use ${ORANGE}arrows${DARK_GRAY} to navigate, ${ORANGE}Enter${DARK_GRAY} to select${RESET}"
        echo ""
        
        for i in "${!options[@]}"; do
            if [ $i -eq $selected_index ]; then
                echo -e "    ${ORANGE}${ICON_FILLED}${RESET} ${WHITE}${options[$i]}${RESET}"
            else
                echo -e "    ${DARK_GRAY}${ICON_EMPTY} ${options[$i]}${RESET}"
            fi
        done
        
        case $(read_key) in
            "UP")   ((selected_index--)) || true; [ $selected_index -lt 0 ] && selected_index=$((options_count - 1)) ;;
            "DOWN") ((selected_index++)) || true; [ $selected_index -ge $options_count ] && selected_index=0 ;;
            "ENTER")
                tput cnorm
                MENU_RESULT="${options[$selected_index]}"
                return ;;
        esac
    done
}

show_multi_select_menu() {
    # Arguments: Title, PreviousInfo, Option1, Option2, ...
    local title="$1"
    local prev_info="$2"
    shift 2
    local options=("$@")
    local selected_index=0
    local options_count=${#options[@]}
    
    # Initialize selection state (default: first option selected)
    declare -a selected
    for i in "${!options[@]}"; do selected[$i]=0; done
    selected[0]=1

    tput civis
    while true; do
        clear
        show_banner
        [ -n "$prev_info" ] && { echo -e "$prev_info"; echo ""; }
        
        echo -e "  ${WHITE}$title${RESET}"
        echo -e "  ${DARK_GRAY}Use ${ORANGE}arrows${DARK_GRAY} to navigate, ${ORANGE}Space${DARK_GRAY} to toggle, ${ORANGE}Enter${DARK_GRAY} to confirm${RESET}"
        echo ""
        
        for i in "${!options[@]}"; do
            local icon="${ICON_CHECKBOX_OFF}"
            local color="${DARK_GRAY}"
            [ ${selected[$i]} -eq 1 ] && { icon="${ICON_CHECKBOX_ON}"; color="${ORANGE}"; }
            
            if [ $i -eq $selected_index ]; then
                echo -e "    ${color}${icon}${RESET} ${WHITE}${options[$i]}${RESET}"
            else
                echo -e "    ${color}${icon}${RESET} ${DARK_GRAY}${options[$i]}${RESET}"
            fi
        done
        
        case $(read_key) in
            "UP")    ((selected_index--)) || true; [ $selected_index -lt 0 ] && selected_index=$((options_count - 1)) ;;
            "DOWN")  ((selected_index++)) || true; [ $selected_index -ge $options_count ] && selected_index=0 ;;
            "SPACE") 
                if [ ${selected[$selected_index]} -eq 1 ]; then selected[$selected_index]=0
                else selected[$selected_index]=1; fi ;;
            "ENTER")
                tput cnorm
                local result=""
                for i in "${!options[@]}"; do
                    [ ${selected[$i]} -eq 1 ] && result="${result:+$result, }${options[$i]}"
                done
                MENU_RESULT="${result:-${options[0]}}" # Default to first if none
                return ;;
        esac
    done
}

show_confirm_menu() {
    local summary="$1"
    local selected_index=0 # 0=Yes, 1=No
    
    tput civis
    while true; do
        clear
        show_banner
        
        echo -e "  ${DARK_GRAY}----------------------------------------${RESET}"
        echo -e "  ${WHITE}Build Summary${RESET}"
        echo -e "  ${DARK_GRAY}----------------------------------------${RESET}"
        echo ""
        echo -e "$summary"
        echo ""
        echo -e "  ${DARK_GRAY}----------------------------------------${RESET}"
        echo ""
        echo -e "  ${WHITE}Proceed with build and upload?${RESET}"
        echo ""
        
        if [ $selected_index -eq 0 ]; then
            echo -e "    ${ORANGE}${ICON_FILLED}${RESET} ${WHITE}Yes${RESET}     ${DARK_GRAY}${ICON_EMPTY} No${RESET}"
        else
            echo -e "    ${DARK_GRAY}${ICON_EMPTY} Yes${RESET}     ${ORANGE}${ICON_FILLED}${RESET} ${WHITE}No${RESET}"
        fi
        
        case $(read_key) in
            "LEFT"|"RIGHT") selected_index=$((1 - selected_index)) ;;
            "UP"|"DOWN")    selected_index=$((1 - selected_index)) ;;
            "ENTER") 
                tput cnorm
                [ $selected_index -eq 0 ] && MENU_RESULT="yes" || MENU_RESULT="no"
                return ;;
        esac
    done
}

show_text_input() {
    local prompt="$1"
    local default_value="$2"
    local prev_info="$3"
    
    clear
    show_banner
    [ -n "$prev_info" ] && { echo -e "$prev_info"; echo ""; }
    
    echo -e "  ${WHITE}$prompt${RESET}"
    echo -e "  ${DARK_GRAY}Press ${ORANGE}Enter${DARK_GRAY} for default${RESET}"
    echo ""
    echo -e -n "    ${ORANGE}${ICON_ARROW}${RESET} "
    
    read -r user_input
    MENU_RESULT="${user_input:-$default_value}"
}

show_multiline_input() {
    local prompt="$1"
    local default_value="$2"
    local prev_info="$3"
    
    clear
    show_banner
    [ -n "$prev_info" ] && { echo -e "$prev_info"; echo ""; }
    
    echo -e "  ${WHITE}$prompt${RESET}"
    echo -e "  ${DARK_GRAY}Enter multiple lines. Press ${ORANGE}Enter twice${DARK_GRAY} (empty line) to finish.${RESET}"
    echo -e "  ${DARK_GRAY}Leave empty and press Enter for default.${RESET}"
    echo ""
    
    local lines=""
    local line_count=0
    
    while true; do
        echo -e -n "    ${ORANGE}${ICON_ARROW}${RESET} "
        read -r line
        
        # If first line is empty, use default
        if [ $line_count -eq 0 ] && [ -z "$line" ]; then
            MENU_RESULT="$default_value"
            return
        fi
        
        # Empty line after content means done
        if [ -z "$line" ] && [ $line_count -gt 0 ]; then
            break
        fi
        
        # Append line
        if [ $line_count -eq 0 ]; then
            lines="$line"
        else
            lines="$lines\\n$line"
        fi
        line_count=$((line_count + 1))
    done
    
    MENU_RESULT="$lines"
}




# ==============================================================================
# 5. MAIN EXECUTION FLOW
# ==============================================================================
# The core logic of the script starts here.

# --- Step 1: Select Environment ---
show_single_select_menu "Select environment" "" "Uat" "Stage" "Prod"
FLAVOR="$MENU_RESULT"
INFO_0="  ${ORANGE}${ICON_SUCCESS}${RESET} Environment: $FLAVOR"

# --- Step 2: Select Build Type ---
show_single_select_menu "Select build type" "$INFO_0" "Debug" "Release"
BUILD_TYPE="$MENU_RESULT"
INFO_1="${INFO_0}\n  ${ORANGE}${ICON_SUCCESS}${RESET} Build type: $BUILD_TYPE"

# --- Step 3: Enter Description (Multiline) ---
show_multiline_input "Enter release description" "$DEFAULT_DESCRIPTION" "$INFO_1"
DESCRIPTION="$MENU_RESULT"
# Show first line only in info summary
DESCRIPTION_PREVIEW=$(echo -e "$DESCRIPTION" | head -n1)
[ "$(echo -e "$DESCRIPTION" | wc -l)" -gt 1 ] && DESCRIPTION_PREVIEW="${DESCRIPTION_PREVIEW}..."
INFO_2="${INFO_1}\n  ${ORANGE}${ICON_SUCCESS}${RESET} Description: $DESCRIPTION_PREVIEW"

# --- Step 4: Select Groups ---
show_multi_select_menu "Select tester group(s)" "$INFO_2" "${DEFAULT_TESTER_GROUPS[@]}"
SELECTED_GROUPS="$MENU_RESULT"

# --- Step 5: Gather Information ---
GIT_BRANCH=$(get_git_branch)
GIT_AUTHOR=$(get_git_author)

SUMMARY_TEXT="    Environment  $FLAVOR$BUILD_TYPE
    Description  $DESCRIPTION
    Groups       $SELECTED_GROUPS
    Branch       $GIT_BRANCH
    Author       $GIT_AUTHOR"

# --- Step 6: Build Release Notes String ---
RELEASE_NOTES="Environment: $FLAVOR$BUILD_TYPE
Branch: $GIT_BRANCH
Author: $GIT_AUTHOR
Groups: $SELECTED_GROUPS
---
$(echo -e "$DESCRIPTION")"

# --- Step 7: Confirmation ---
show_confirm_menu "$SUMMARY_TEXT"
CONFIRMED="$MENU_RESULT"

if [ "$CONFIRMED" != "yes" ]; then
    clear
    show_banner
    echo -e "  ${ORANGE}Build cancelled.${RESET}"
    echo ""
    exit 0
fi



# --- Step 8: Build & Upload ---
clear
show_banner
echo -e "  ${DARK_GRAY}----------------------------------------${RESET}"
echo -e "  ${WHITE}Building & Uploading${RESET}"
echo -e "  ${DARK_GRAY}----------------------------------------${RESET}"
echo ""
echo -e "  ${ORANGE}${ICON_SUCCESS}${RESET} Release notes prepared"
echo ""

# Run Assembler
TASK_NAME="assemble${FLAVOR}${BUILD_TYPE}"
echo -e "  ${ORANGE}${ICON_ARROW}${RESET} ${DARK_GRAY}Running${RESET} ${ORANGE}./gradlew $TASK_NAME${RESET}"
echo ""
./gradlew "$TASK_NAME"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "  ${ORANGE}${ICON_SUCCESS}${RESET} Build successful"
else
    echo ""
    echo -e "  ${RED}X Build failed${RESET}"
    exit 1
fi

# Run Uploader
UPLOAD_TASK_NAME="appDistributionUpload${FLAVOR}${BUILD_TYPE}"
echo ""
echo -e "  ${ORANGE}${ICON_ARROW}${RESET} ${DARK_GRAY}Running${RESET} ${ORANGE}./gradlew $UPLOAD_TASK_NAME${RESET}"
echo ""

# Use a temporary file to capture output while preserving valid exit codes with pipefail
OUTPUT_FILE=$(mktemp)
set -o pipefail
./gradlew "$UPLOAD_TASK_NAME" --releaseNotes="$RELEASE_NOTES" --groups="$SELECTED_GROUPS" | tee "$OUTPUT_FILE"
UPLOAD_STATUS=$?
set +o pipefail

if [ $UPLOAD_STATUS -eq 0 ]; then
    echo ""
    echo -e "  ${ORANGE}----------------------------------------${RESET}"
    echo -e "  ${ORANGE}${ICON_STAR}${RESET} ${WHITE}Upload complete!${RESET}"
    echo -e "  ${ORANGE}----------------------------------------${RESET}"
    echo ""
    
    # Extract the Tester Share Link
    # Looks for: "Share this release with testers who have access: https://..."
    DISTRIBUTION_URL=$(grep "Share this release with testers who have access:" "$OUTPUT_FILE" | sed -E 's/.*(https:\/\/.*)/\1/' | tr -d '\r')
    
    # Fallback if extraction fails
    if [ -z "$DISTRIBUTION_URL" ]; then
        DISTRIBUTION_URL="https://console.firebase.google.com/project/_/appdistribution"
    fi
    
    rm -f "$OUTPUT_FILE"
else
    rm -f "$OUTPUT_FILE"
    echo ""
    echo -e "  ${RED}X Upload failed${RESET}"
    exit 1
fi

# --- Step 8: Send Slack Notification ---
SLACK_WEBHOOK_URL="$(cat ./webhook-url.txt)"
TIMESTAMP=$(date +%s)

# Format description for Slack (add > prefix for quote formatting)
DESCRIPTION_SLACK=""
while IFS= read -r line || [ -n "$line" ]; do
    # Escape special characters for JSON
    line=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if [ -z "$DESCRIPTION_SLACK" ]; then
        DESCRIPTION_SLACK=">$line"
    else
        DESCRIPTION_SLACK="$DESCRIPTION_SLACK\\n>$line"
    fi
done <<< "$(echo -e "$DESCRIPTION")"

# Build JSON payload using in-memory variables
JSON_PAYLOAD=$(cat <<EOF
{
  "text": "New APK Build Available",
  "blocks": [
    {"type":"header","text":{"type":"plain_text","text":"New APK Build Available","emoji":true}},
    {"type":"divider"},
    {"type":"section","text":{"type":"mrkdwn","text":"*Environment:*  \`${FLAVOR}${BUILD_TYPE}\`"}},
    {"type":"section","text":{"type":"mrkdwn","text":"*Branch:*  \`${GIT_BRANCH}\`"}},
    {"type":"section","text":{"type":"mrkdwn","text":"*Author:*  ${GIT_AUTHOR}"}},
    {"type":"section","text":{"type":"mrkdwn","text":"*Tester Groups:*  \`${SELECTED_GROUPS}\`"}},
    {"type":"section","text":{"type":"mrkdwn","text":"*Description:*\n${DESCRIPTION_SLACK}"}},
    {"type":"divider"},
    {"type":"section","text":{"type":"mrkdwn","text":"*Download & Install*"},"accessory":{"type":"button","text":{"type":"plain_text","text":"Download APK","emoji":true},"url":"${DISTRIBUTION_URL}","style":"primary"}},
    {"type":"divider"},
    {"type":"context","elements":[{"type":"mrkdwn","text":"*Firebase App Distribution* | <!date^${TIMESTAMP}^{date_short_pretty} at {time}|Posted>"}]}
  ]
}
EOF
)

curl -k -X POST \
  -H "Content-Type: application/json" \
  --data "$JSON_PAYLOAD" \
  "$SLACK_WEBHOOK_URL"

echo ""
echo -e "  ${ORANGE}${ICON_SUCCESS}${RESET} Slack notification sent"



