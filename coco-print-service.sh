#!/usr/bin/env bash

# CoCo Print Service
# Monitors a directory for new files and prints them to a CUPS printer.

# Default configuration file location
CONFIG_FILE="${CONFIG_FILE:-/etc/coco-print-service.conf}"

# Source configuration if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Warning: Config file $CONFIG_FILE not found, using defaults"
fi

# Set defaults if not configured
MONITOR_DIR="${MONITOR_DIR:-/cocoprints}"
PRINTER_NAME="${PRINTER_NAME:-default}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
WATCH_PATTERN="${WATCH_PATTERN:-.*\.txt$}"
ARCHIVE_DIR="${ARCHIVE_DIR:-archive}"
LOG_FILE="${LOG_FILE:-coco-print.log}"

# Full paths
ARCHIVE_PATH="$MONITOR_DIR/$ARCHIVE_DIR"
LOG_PATH="$MONITOR_DIR/$LOG_FILE"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Only log if the level is appropriate
    case "$LOG_LEVEL" in
        DEBUG) levels="DEBUG INFO WARN ERROR" ;;
        INFO)  levels="INFO WARN ERROR" ;;
        WARN)  levels="WARN ERROR" ;;
        ERROR) levels="ERROR" ;;
        *) levels="INFO WARN ERROR" ;;
    esac

    if [[ " $levels " == *" $level "* ]]; then
        echo "[$timestamp] [$level] $message" | tee -a "$LOG_PATH"
    fi
}

get_timestamp() {
    date '+%Y%m%d%H%M%S'
}

process_file() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    local timestamp=$(get_timestamp)
    local extension="${filename##*.}"
    local basename="${filename%.*}"
    local new_filename="${basename}_${timestamp}.${extension}"
    local new_filepath="$MONITOR_DIR/$new_filename"
    local archive_filepath="$ARCHIVE_PATH/$new_filename"

    log "INFO" "Processing file: $filename"

    # Rename file with timestamp
    if mv "$filepath" "$new_filepath"; then
        log "INFO" "Renamed $filename to $new_filename"
    else
        log "ERROR" "Failed to rename $filename to $new_filename"
        return 1
    fi

    # Check if file has carriage returns and fix them
    if grep -q $'\r' "$new_filepath"; then
        log "INFO" "File contains carriage returns, converting to newlines..."
        if sed -i 's/\r/\n/g' "$new_filepath"; then
            log "INFO" "Successfully converted carriage returns to newlines in $new_filename"
        else
            log "WARN" "Failed to convert carriage returns in $new_filename, continuing anyway"
        fi
    fi

    # Print the file
    log "INFO" "Printing $new_filename to printer $PRINTER_NAME"
    if lp -d "$PRINTER_NAME" "$new_filepath" 2>&1 | while read -r line; do
        log "DEBUG" "lp output: $line"
    done; then
        log "INFO" "Successfully printed $new_filename"
    else
        log "ERROR" "Failed to print $new_filename"
        # Continue with archiving even if printing fails
    fi

    # Move to archive
    log "DEBUG" "Attempting to archive $new_filepath to $archive_filepath"
    if mv "$new_filepath" "$archive_filepath" 2>&1; then
        log "INFO" "Archived $new_filename"
    else
        local mv_error=$?
        log "ERROR" "Failed to archive $new_filename (exit code: $mv_error)"
        log "ERROR" "Source: $new_filepath"
        log "ERROR" "Destination: $archive_filepath"
        log "ERROR" "Archive directory exists: $(test -d "$ARCHIVE_PATH" && echo "yes" || echo "no")"
        log "ERROR" "Archive directory writable: $(test -w "$ARCHIVE_PATH" && echo "yes" || echo "no")"
        return 1
    fi

    log "INFO" "Completed processing of $new_filename"
}

check_dependencies() {
    local deps=("inotifywait" "lp")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR" "Missing dependencies: ${missing[*]}"
        log "ERROR" "Please install: inotify-tools cups-client"
        exit 1
    fi
}

validate_printer() {
    if ! lpstat -p "$PRINTER_NAME" >/dev/null 2>&1; then
        log "WARN" "Printer '$PRINTER_NAME' may not be available"
        log "INFO" "Available printers:"
        lpstat -p 2>/dev/null | while read -r line; do
            log "INFO" "  $line"
        done || log "WARN" "Could not list printers"
    else
        log "INFO" "Printer '$PRINTER_NAME' is available"
    fi
}

cleanup() {
    log "INFO" "Received shutdown signal, cleaning up..."
    if [[ -n "${INOTIFY_PID:-}" ]]; then
        kill "$INOTIFY_PID" 2>/dev/null || true
    fi
    log "INFO" "CoCo Print Service stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT

main() {
    log "INFO" "Starting CoCo Print Service"
    log "INFO" "Monitor directory: $MONITOR_DIR"
    log "INFO" "Printer: $PRINTER_NAME"
    log "INFO" "Log level: $LOG_LEVEL"
    log "INFO" "Watch pattern: $WATCH_PATTERN"

    # Ensure archive directory exists
    if [[ ! -d "$ARCHIVE_PATH" ]]; then
        log "INFO" "Creating archive directory: $ARCHIVE_PATH"
        if ! mkdir -p "$ARCHIVE_PATH"; then
            log "ERROR" "Failed to create archive directory: $ARCHIVE_PATH"
            exit 1
        fi
    fi

    check_dependencies
    validate_printer

    # Exclude log file and archive directory
    local exclude_pattern="($LOG_FILE|$ARCHIVE_DIR)"

    # Start monitoring
    log "INFO" "Starting directory monitoring..."
    log "DEBUG" "Include pattern: $WATCH_PATTERN"
    log "DEBUG" "Exclude pattern: $exclude_pattern"

    inotifywait -m -e close_write,moved_to \
        --format '%w%f' \
        --include "$WATCH_PATTERN" \
        "$MONITOR_DIR" | while read -r filepath; do

        # Check if file should be excluded
        local filename=$(basename "$filepath")
        if [[ "$filename" =~ $exclude_pattern ]]; then
            log "DEBUG" "Skipping excluded file: $filename"
            continue
        fi

        # Small delay to ensure file is completely written
        sleep 0.5
        if [[ -f "$filepath" ]]; then
            process_file "$filepath"
        fi
    done &

    INOTIFY_PID=$!
    log "INFO" "CoCo Print Service is running (PID: $$, inotify PID: $INOTIFY_PID)"

    # Wait for the inotifywait process
    wait $INOTIFY_PID
}

main "$@"
