#! /bin/bash

#>>
# Various Terminal Output Functions
#<< see do_help_doc()
NoColor='\033[0m'           # Text Reset
BGreen='\033[1;32m'        # Yellow
BYellow='\033[1;33m'        # Yellow
BCyan='\033[1;36m'          # Cyan

# Print an error meesage
# $1 == Message
function print_error() {
    if [[ -z "$1" ]]; then exit 1; fi
    echo -e "${BYellow}$1${NoColor}" >&2
}

# Print an error meesage
# $1 == Message
function print_warning() {
    if [[ -z "$1" ]]; then exit 1; fi
    echo -e "${BCyan}$1${NoColor}" >&2 
}
# Print an error meesage
# $1 == Message
function print_success() {
    if [[ -z "$1" ]]; then exit 1; fi
    echo -e "${BGreen}$1${NoColor}" >&2 
}