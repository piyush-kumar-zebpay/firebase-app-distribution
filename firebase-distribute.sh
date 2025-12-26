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
RELEASE_NOTES_DIR="${APP_MODULE_DIR}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_DIR}/release-notes.txt"

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

# ==============================================================================
# 5. MAIN EXECUTION FLOW
# ==============================================================================
# The core logic of the script starts here.

# --- Step 1: Select Build Type ---
show_single_select_menu "Select build type" "" "Debug" "Release"
BUILD_TYPE="$MENU_RESULT"
INFO_1="  ${ORANGE}${ICON_SUCCESS}${RESET} Build type: $BUILD_TYPE"

# --- Step 2: Enter Description ---
show_text_input "Enter release description" "$DEFAULT_DESCRIPTION" "$INFO_1"
DESCRIPTION="$MENU_RESULT"
INFO_2="${INFO_1}\n  ${ORANGE}${ICON_SUCCESS}${RESET} Description: $DESCRIPTION"

# --- Step 3: Select Groups ---
show_multi_select_menu "Select tester group(s)" "$INFO_2" "${DEFAULT_TESTER_GROUPS[@]}"
SELECTED_GROUPS="$MENU_RESULT"

# --- Step 4: Gather Information ---
GIT_BRANCH=$(get_git_branch)
GIT_AUTHOR=$(get_git_author)

SUMMARY_TEXT="    Build Type   $BUILD_TYPE
    Description  $DESCRIPTION
    Groups       $SELECTED_GROUPS
    Branch       $GIT_BRANCH
    Author       $GIT_AUTHOR"

# --- Step 5: Save Release Notes ---
mkdir -p "$RELEASE_NOTES_DIR"
cat > "$RELEASE_NOTES_FILE" << EOF
BuildType: $BUILD_TYPE
Branch: $GIT_BRANCH
Description: $DESCRIPTION
Author: $GIT_AUTHOR
Groups: $SELECTED_GROUPS
EOF

# --- Step 6: Confirmation ---
show_confirm_menu "$SUMMARY_TEXT"
CONFIRMED="$MENU_RESULT"

if [ "$CONFIRMED" != "yes" ]; then
    clear
    show_banner
    echo -e "  ${ORANGE}Build cancelled.${RESET}"
    echo ""
    exit 0
fi

# --- Step 7: Build & Upload ---
clear
show_banner
echo -e "  ${DARK_GRAY}----------------------------------------${RESET}"
echo -e "  ${WHITE}Building & Uploading${RESET}"
echo -e "  ${DARK_GRAY}----------------------------------------${RESET}"
echo ""
echo -e "  ${ORANGE}${ICON_SUCCESS}${RESET} Release notes saved"
echo ""

# Run Assembler
echo -e "  ${ORANGE}${ICON_ARROW}${RESET} ${DARK_GRAY}Running${RESET} ${ORANGE}./gradlew assemble${BUILD_TYPE}${RESET}"
echo ""
./gradlew "assemble${BUILD_TYPE}"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "  ${ORANGE}${ICON_SUCCESS}${RESET} Build successful"
else
    echo ""
    echo -e "  ${RED}X Build failed${RESET}"
    exit 1
fi

# Run Uploader
echo ""
echo -e "  ${ORANGE}${ICON_ARROW}${RESET} ${DARK_GRAY}Running${RESET} ${ORANGE}./gradlew appDistributionUpload${BUILD_TYPE}${RESET}"
echo ""
./gradlew "appDistributionUpload${BUILD_TYPE}"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "  ${ORANGE}----------------------------------------${RESET}"
    echo -e "  ${ORANGE}${ICON_STAR}${RESET} ${WHITE}Upload complete!${RESET}"
    echo -e "  ${ORANGE}----------------------------------------${RESET}"
    echo ""
else
    echo ""
    echo -e "  ${RED}X Upload failed${RESET}"
    exit 1
fi
