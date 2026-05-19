#!/usr/bin/env bash

# james.sh version 0.1

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_INSTALLATION_PATH="$HOME/.local/bin"

BASHRC_PATH="$HOME/.bashrc"

LOGFILE="./james.log"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local script_name=$(basename "$0")
    echo "[$timestamp] [$script_name] [$level] $message" | tee -a "$LOGFILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARNING" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { [[ "$LOG_LEVEL" == "DEBUG" ]] && log "DEBUG" "$@"; }

# detect if fish is installed on the system
if type fish >/dev/null 2>&1; then
    log_debug "detected fish shell"
    FISH_SHELL_INSTALLED=1
    FISH_SHELL_CONFIG="$HOME/.config/fish/config.fish"
else
    FISH_SHELL_INSTALLED=0
fi

log_debug "FISH_SHELL_INSTALLED=$FISH_SHELL_INSTALLED"

datestamp() {
    # return date in YYYY-MM-DD (ISO 8601)
    date +%F
}

comment_string() {
    echo "$(datestamp): automatically added by james.sh"
}

are_same_file() {
    # Check if both files exist
    [ -e "$1" ] && [ -e "$2" ] || return 1

    # Try stat with Linux format first
    if stat -c "%d:%i" "$1" >/dev/null 2>&1; then
        [ "$(stat -c "%d:%i" "$1")" = "$(stat -c "%d:%i" "$2")" ]
    # Try stat with BSD/macOS format
    elif stat -f "%d:%i" "$1" >/dev/null 2>&1; then
        [ "$(stat -f "%d:%i" "$1")" = "$(stat -f "%d:%i" "$2")" ]
    else
        return 1
    fi
}

# safely add line to file
add_to_file() {
    # check if two arguments are passed in, otherwise fail
    if [ $# -ne 2 ]; then
        log_debug "1=$1"
        log_debug "2=$2"
        log_debug "#=$#"
        log_error "two arguments must be provided to add_to_file: first path to file, second content to write to file"
        return 1
    fi

    # first argument is the file to append, second the content to append
    local file="$1"
    local content="$2"
    log_debug "file=$file"
    log_debug "content=$content"

    # get the directory part of the path
    file_dir=$(dirname "$file")

    # create the directory if it doesn't exist
    mkdir -p "$file_dir"

    # create the file if it doesn't exist
    if [ ! -f "$file" ]; then
        touch "$file"
        log_info "had to create $file as it didn't exist"
    fi

    # check if the line we want to add doesn't already exist
    if ! grep -qF "$content" "$file"; then
        echo "# $(comment_string)" >> $file
        echo $content >> $file
    fi
}

add_alias() {
    # check if two arguments are passed in, otherwise fail
    if [ $# -ne 2 ]; then
        log_error "two arguments must be provided to add_alias: first the alias name, second the command"
        return 1
    fi

    # first argument is the alias name, second is the command
    local alias="$1"
    local command="$2"
    log_debug "alias=$alias"
    log_debug "command=$command"

    # add alias line to bashrc
    local alias_string="alias $alias='$command'"
    log_debug "BASHRC_PATH=$BASHRC_PATH"
    log_debug "alias_string=$alias_string"
    add_to_file "$BASHRC_PATH" "$alias_string"
    log_info "added shorthand via appending $alias_string to $BASHRC_PATH"

    # source bashrc
    source $BASHRC_PATH

    # write alias also to fish config if fish is installed
    if [ "$FISH_SHELL_INSTALLED" -eq 1 ]; then
        add_to_file "$FISH_SHELL_CONFIG" "$alias_string"
        log_info "added shorthand via appending $alias_string to $FISH_SHELL_CONFIG"
        source $FISH_SHELL_CONFIG
    fi
}

installation_prompt() {
    log_warn "I noticed you are running james from $SCRIPT_PATH. If you want to install it to $SCRIPT_INSTALLATION_PATH you can run:"
    log_warn
    log_warn "james.sh install"
    log_warn
}

install() {
    # if first argument exists
    if [ -n "$1" ]; then
        log_info "installing $1"
    # if just james.sh install has been run
    else
        log_info "installing james.sh"
        install_james
    fi
}

install_james() {
    # copy script to standard location
    mkdir -p $SCRIPT_INSTALLATION_PATH
    cp $SCRIPT_PATH $SCRIPT_INSTALLATION_PATH
    chmod +x "$SCRIPT_INSTALLATION_PATH/james.sh"
    log_info "copied james to $SCRIPT_INSTALLATION_PATH/james.sh"

    # make sure installation path is in $PATH
    local export_string="export PATH=$SCRIPT_INSTALLATION_PATH:\$PATH"
    add_to_file "$BASHRC_PATH" "$export_string"
    log_info "ensured that $SCRIPT_INSTALLATION_PATH is in \$PATH"

    # if fish is installed, add it there as well
    if [ "$FISH_SHELL_INSTALLED" -eq 1 ]; then
        fish -c "fish_add_path $SCRIPT_INSTALLATION_PATH"
        log_info "added $SCRIPT_INSTALLATION_PATH to fish path"
    fi

    # add alias for james.sh
    add_alias "j" "james.sh"

    log_info "installed james"
}


update() {
    # if first argument exists
    if [ -n "$1" ]; then
        log_info "updating $1"
    # if just james.sh update has been run
    else
        log_info "updating james.sh"
        update_james
    fi
}

update_james() {
    log_info "not implemented yet"
}

show_help() {
    cat << EOF
Usage: $0 <command> [options]

Commands:
  install   install new modules, or if used without argument, install james.sh
  update    update a module, or if used without argument, update james.sh
  logs      show log file
  help      show this help message

Logging:
  All logs can be found in $LOGFILE. Log level $LOG_LEVEL is currently active.

Examples:
  $0 install
  $0 status
EOF
}

show_logs() {
    # check if bat exists
    if command -v bat >/dev/null 2>&1; then
        BAT_CMD="bat"
        log_info "using bat for display"
    else
        BAT_CMD="cat"
        log_info "bat not found, falling back to cat"
    fi

    # Use the appropriate command
    $BAT_CMD $LOGFILE
}

# Main script logic
main() {
    # default to help command
    local command="${1:-help}"
    # shift arguments given by 1 and make sure it can't fail
    shift || true

    log_debug "SCRIPT_DIR=$SCRIPT_DIR"
    log_debug "SCRIPT_INSTALLATION_PATH=$SCRIPT_INSTALLATION_PATH"
    if ! are_same_file $SCRIPT_DIR $SCRIPT_INSTALLATION_PATH; then
        installation_prompt
    fi

    case "$command" in
        install)
            install "$@"
            ;;
        update)
            update "$@"
            ;;
        logs)
            show_logs "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Error: Unknown command '$command'" >&2
            show_help >&2
            exit 1
            ;;
    esac
}

# run main function with all arguments
main "$@"
