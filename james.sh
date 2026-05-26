#!/usr/bin/env bash

# james.sh version 0.1

set -o pipefail

LOGFILE="./james.log"
LOG_LEVEL="${LOG_LEVEL:-DEBUG}"

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_INSTALLATION_PATH="$HOME/.local/bin"
JAMES_CONFIG="$SCRIPT_INSTALLATION_PATH/james-config.json"

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
init_config() {
    # check if config file exists
    if [ ! -f "$JAMES_CONFIG" ]; then
        log_debug "pwd=$(pwd)"
        if [ -f "$(pwd)/config.json" ]; then
            log_info "copied over config from $(pwd)/config.json --> $JAMES_CONFIG"
            cp "$(pwd)/config.json" "$JAMES_CONFIG"
        else
            add_to_file "$JAMES_CONFIG" "{}"
        fi
    fi
}
# make sure config exists
init_config

OS_TYPE=$(uname -s)



log_debug "SCRIPT_DIR=$SCRIPT_DIR"
log_debug "SCRIPT_PATH=$SCRIPT_PATH"

BASHRC_PATH="$HOME/.bashrc"

TODO_TXT_CONFIG_PATH=$(jq -r '.todo_txt_config' "$JAMES_CONFIG" | envsubst)


log_debug "JAMES_CONFIG=$JAMES_CONFIG"
log_debug "TODO_TXT_CONFIG_PATH=$TODO_TXT_CONFIG_PATH"

# detect if fish is installed on the system
if command -v fish >/dev/null 2>&1; then
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

add_json_object() {
    # adds a JSON object to the provided root level key name; if the key doesn't exist, it will create an array, if it exists, but is not an array, it will fail.
    _file="$1"
    _node="$2" # root-level key, e.g. "shortcuts"
    _obj="$3" # valid JSON object string, e.g. '{"name":"x"}'
    _tmp="${_file}.tmp.$$"

    jq --arg node "$_node" \
       --argjson obj "$_obj" '
       if has($node) and (.[$node] | type) != "array" then
           "Error: \($node) is not an array" | halt_error(1)
       else
           .[$node] //= [] | .[$node] += [$obj]
       end
    ' "$_file" > "$_tmp" || { rm -f "$_tmp"; return 1; }

    mv "$_tmp" "$_file"
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

set_environment_var() {
    # make name all uppercase
    local name=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
    local value="$2"
    # add export line to bashrc
    add_to_file "$BASHRC_PATH" "export $var=$value"
    # source bashrc so that it takes effect
    source "$BASHRC_PATH"

    # if fish is installed, create var there too
    if [ "$FISH_SHELL_INSTALLED" -eq 1 ]; then
        fish -c "set -Ux $name $value"
    fi

    log_info "set environment var: $name=$value"
}

check_if_git_is_installed() {
    # check if git is installed
    if ![ command -v git >/dev/null 2>&1 ]; then
        log_warn "git is not installed on your system"
    fi
}

dependency_git() {
    # check if git is installed
    if ![ command -v git >/dev/null 2>&1 ]; then
        # go through different OS types
        case "$OS_TYPE" in
            Darwin*)
                log_info "detected macOS"
                log_error "Git needs to be installed through the command line XCode thingy, aborting therefore. Please try to run git from the CLI."
                return 1
                ;;
            Linux*)
                log_info "detected Linux"
                log_info "trying to install git via apt"
                # TODO: add Fedora etc
                apt install git
                ;;
            *)
                log_error "unsupported OS: $OS_TYPE"
                log_error "dependency git was not found"
                ;;
        esac
    fi
}

dependency_brew() {
    # check if brew is installed
    if ![ command -v brew >/dev/null 2>&1 ]; then
        # install brew
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}

install_todo_txt_macos() {
    dependency_brew
    brew install todo-txt
    cp -n "$(brew --prefix)/opt/todo-txt/todo.cfg" "$HOME/.todo.cfg"
}

install_todo_txt() {
    # go through different OS types
    case "$OS_TYPE" in
        Darwin*)
            log_info "detected macOS"
            install_todo_txt_macos
            ;;
        Linux*)
            log_info "detected Linux"
            install_todo_txt_linux
            ;;
        *)
            log_error "unsupported OS: $OS_TYPE"
            ;;
    esac
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
  config    show config file
  logs      show log file
  help      show this help message

Logging:
  All logs can be found in $LOGFILE. Log level $LOG_LEVEL is currently active.

Examples:
  $0 install
  $0 status
EOF
}

show_help_debug() {
    cat << EOF
Usage: $0 debug LEVEL

LEVEL:
  DEBUG     show all logs
  INFO      only report up to info level
  WARNING   report everything up to warning level
  ERROR     only report errors

Logging:
  All logs can be found in $LOGFILE. Log level $LOG_LEVEL is currently active.
EOF
}

change_log_level() {
    local level_new="${1:-DEBUG}"
    local level_old="$LOG_LEVEL"

    set_environment_var "LOG_LEVEL" $level_new
    log_info "changed log level from $level_old --> $level_new"
}

debug() {
    # default to help command
    local level="${1:-list}"
    # shift arguments given by 1 and make sure it can't fail
    shift || true

    case "$level" in
        DEBUG|debug)
            change_log_level "DEBUG"
            ;;
        INFO|info)
            change_log_level "INFO"
            ;;
        WARNING|warning)
            change_log_level "WARNING"
            ;;
        ERROR|error)
            change_log_level "ERROR"
            ;;
        help|list)
            show_help_debug
            ;;
        *)
            log_error "Unknown level '$level'" >&2
            show_help_debug >&2
            exit 1
            ;;
    esac
}

show_text_file() {
    _file="$1"

    # check if bat exists
    if command -v bat >/dev/null 2>&1; then
        BAT_CMD="bat"
        log_info "using bat for display"
    else
        BAT_CMD="cat"
        log_info "bat not found, falling back to cat"
    fi
    # Use the appropriate command
    $BAT_CMD $_file
}

show_logs() {
    show_text_file $LOGFILE
}

show_config() {
    show_text_file $JAMES_CONFIG
}

show_help_shortcut() {
    cat << EOF
Usage: $0 shortcut <command> [options]

Commands:
  list      lists all currently installed shortcuts
  new       create new shortcut
  rm        remove a shortcut
  help      show this help message
EOF
}

shortcut_list() {
    log_info "not implemented yet"
}

shortcut_new() {
    log_info "not implemented yet"
}

shortcut_rm() {
    log_info "not implemented yet"
}

shortcut() {
    # default to help command
    local subcommand="${1:-list}"
    # shift arguments given by 1 and make sure it can't fail
    shift || true

    case "$subcommand" in
        list)
            shortcut_list "$@"
            ;;
        new)
            shortcut_new "$@"
            ;;
        rm)
            shortcut_rm "$@"
            ;;
        help|--help|-h)
            show_help_shortcut
            ;;
        *)
            log_error "Unknown command '$subcommand'" >&2
            show_help_shortcut >&2
            exit 1
            ;;
    esac
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
        config)
            show_config "$@"
            ;;
        shortcut)
            shortcut "$@"
            ;;
        debug)
            debug "$@"
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
