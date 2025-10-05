#!/bin/bash
################################################################################
# PostgreSQL Log Rotation and Retention Script
#
# Purpose: Automated log cleanup for GDPR Article 5(1)(e) compliance
#          (Storage Limitation - data kept no longer than necessary)
#
# Compliance: GDPR Article 30 (Records of Processing Activities)
#             GDPR Article 5(1)(e) (Storage Limitation)
#             SOC2 CC7.1 (System Monitoring)
#
# Author: Dr. Kenji Tanaka (Security Engineer)
# Date: 2025-10-05
# Sprint: 1, Day 3
#
# Retention Policies:
#   - Development Environment: 90 days
#   - Production Environment: 7 years (2,555 days)
#
# Usage:
#   ./rotate-logs.sh [development|production]
#   Default: development
#
# Scheduling:
#   Development: Daily via cron (0 2 * * * /path/to/rotate-logs.sh development)
#   Production: Daily via cron with archival to S3/object storage
#
################################################################################

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Configuration
SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${POSTGRES_LOG_DIR:-/var/log/postgresql}"
ARCHIVE_DIR="${POSTGRES_LOG_ARCHIVE_DIR:-/var/log/postgresql/archive}"
ROTATION_LOG="/var/log/taifabase-log-rotation.log"

# Environment-specific retention (in days)
RETENTION_DEV=90        # 90 days for development
RETENTION_PROD=2555     # 7 years for production (GDPR compliance)

# Determine environment (default: development)
ENVIRONMENT="${1:-development}"

# Set retention period based on environment
if [ "$ENVIRONMENT" == "production" ]; then
    RETENTION_DAYS=$RETENTION_PROD
    ENABLE_ARCHIVAL=true
else
    RETENTION_DAYS=$RETENTION_DEV
    ENABLE_ARCHIVAL=false
fi

################################################################################
# Logging Functions
################################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$ROTATION_LOG"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

################################################################################
# Validation Functions
################################################################################

validate_environment() {
    if [ ! -d "$LOG_DIR" ]; then
        log_error "PostgreSQL log directory not found: $LOG_DIR"
        log_error "Please set POSTGRES_LOG_DIR environment variable or ensure directory exists"
        exit 1
    fi

    if [ ! -w "$LOG_DIR" ]; then
        log_error "PostgreSQL log directory not writable: $LOG_DIR"
        log_error "Please check directory permissions"
        exit 1
    fi

    log_info "Log directory validated: $LOG_DIR"
}

################################################################################
# Archive Functions (Production Only)
################################################################################

archive_logs() {
    if [ "$ENABLE_ARCHIVAL" != "true" ]; then
        log_info "Log archival disabled for $ENVIRONMENT environment"
        return 0
    fi

    log_info "Archiving logs older than $RETENTION_DAYS days to long-term storage..."

    # Create archive directory if it doesn't exist
    mkdir -p "$ARCHIVE_DIR"

    # Find logs to archive (older than retention period, not already archived)
    local logs_to_archive
    logs_to_archive=$(find "$LOG_DIR" -maxdepth 1 -name "postgresql-*.log" -mtime +$RETENTION_DAYS -type f)

    if [ -z "$logs_to_archive" ]; then
        log_info "No logs found for archival"
        return 0
    fi

    local archive_count=0
    while IFS= read -r log_file; do
        local log_filename
        log_filename=$(basename "$log_file")

        # Compress and move to archive directory
        if gzip -c "$log_file" > "$ARCHIVE_DIR/${log_filename}.gz"; then
            log_info "Archived: $log_filename -> $ARCHIVE_DIR/${log_filename}.gz"
            archive_count=$((archive_count + 1))
        else
            log_error "Failed to archive: $log_filename"
        fi
    done <<< "$logs_to_archive"

    log_info "Archived $archive_count log files"

    # TODO: Production enhancement - Upload archives to S3/Cloud Storage
    # Example: aws s3 sync "$ARCHIVE_DIR" s3://taifabase-logs-archive/postgresql/
    # Example: gsutil rsync -r "$ARCHIVE_DIR" gs://taifabase-logs-archive/postgresql/
}

################################################################################
# Cleanup Functions
################################################################################

cleanup_old_logs() {
    log_info "Removing logs older than $RETENTION_DAYS days from $LOG_DIR..."

    # Find and count logs to delete
    local logs_to_delete
    logs_to_delete=$(find "$LOG_DIR" -maxdepth 1 -name "postgresql-*.log" -mtime +$RETENTION_DAYS -type f)

    if [ -z "$logs_to_delete" ]; then
        log_info "No logs found exceeding retention period"
        return 0
    fi

    # Count logs before deletion
    local delete_count
    delete_count=$(echo "$logs_to_delete" | wc -l)

    # Calculate total size of logs to delete
    local total_size
    total_size=$(echo "$logs_to_delete" | xargs du -ch | grep total$ | awk '{print $1}')

    log_info "Found $delete_count log files exceeding retention period (Total size: $total_size)"

    # Delete logs
    local deleted_count=0
    local failed_count=0

    while IFS= read -r log_file; do
        local log_filename
        log_filename=$(basename "$log_file")

        if rm -f "$log_file"; then
            log_info "Deleted: $log_filename"
            deleted_count=$((deleted_count + 1))
        else
            log_error "Failed to delete: $log_filename"
            failed_count=$((failed_count + 1))
        fi
    done <<< "$logs_to_delete"

    log_info "Cleanup complete: $deleted_count deleted, $failed_count failed"
}

cleanup_old_archives() {
    if [ "$ENABLE_ARCHIVAL" != "true" ] || [ ! -d "$ARCHIVE_DIR" ]; then
        return 0
    fi

    log_info "Removing archived logs older than $RETENTION_DAYS days from $ARCHIVE_DIR..."

    # In production, archives should be kept longer (e.g., move to cold storage)
    # For now, we'll keep them for the retention period
    local archives_to_delete
    archives_to_delete=$(find "$ARCHIVE_DIR" -name "postgresql-*.log.gz" -mtime +$RETENTION_DAYS -type f)

    if [ -z "$archives_to_delete" ]; then
        log_info "No archived logs found exceeding retention period"
        return 0
    fi

    local delete_count
    delete_count=$(echo "$archives_to_delete" | wc -l)

    log_info "Removing $delete_count archived logs exceeding retention period"
    echo "$archives_to_delete" | xargs rm -f

    log_info "Archived logs cleanup complete"
}

################################################################################
# Statistics Functions
################################################################################

generate_statistics() {
    log_info "Generating log retention statistics..."

    # Current log count and size
    local current_log_count
    current_log_count=$(find "$LOG_DIR" -maxdepth 1 -name "postgresql-*.log" -type f | wc -l)

    local current_log_size
    current_log_size=$(du -sh "$LOG_DIR" 2>/dev/null | awk '{print $1}' || echo "0")

    # Oldest log date
    local oldest_log
    oldest_log=$(find "$LOG_DIR" -maxdepth 1 -name "postgresql-*.log" -type f -printf '%T+ %p\n' | sort | head -n1 | awk '{print $1}' || echo "None")

    # Log retention compliance check
    local oldest_log_age_days
    if [ "$oldest_log" != "None" ]; then
        local oldest_log_epoch
        oldest_log_epoch=$(date -d "$oldest_log" +%s)
        local current_epoch
        current_epoch=$(date +%s)
        oldest_log_age_days=$(( (current_epoch - oldest_log_epoch) / 86400 ))
    else
        oldest_log_age_days=0
    fi

    # Compliance status
    local compliance_status
    if [ $oldest_log_age_days -le $RETENTION_DAYS ]; then
        compliance_status="✓ COMPLIANT"
    else
        compliance_status="✗ NON-COMPLIANT (logs exceed retention period)"
    fi

    # Print statistics
    log_info "========================================="
    log_info "Log Retention Statistics"
    log_info "========================================="
    log_info "Environment: $ENVIRONMENT"
    log_info "Retention Policy: $RETENTION_DAYS days"
    log_info "Current Log Count: $current_log_count files"
    log_info "Current Log Size: $current_log_size"
    log_info "Oldest Log Date: $oldest_log"
    log_info "Oldest Log Age: $oldest_log_age_days days"
    log_info "Compliance Status: $compliance_status"
    log_info "========================================="

    # Archive statistics (production only)
    if [ "$ENABLE_ARCHIVAL" == "true" ] && [ -d "$ARCHIVE_DIR" ]; then
        local archive_count
        archive_count=$(find "$ARCHIVE_DIR" -name "postgresql-*.log.gz" -type f | wc -l)

        local archive_size
        archive_size=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | awk '{print $1}' || echo "0")

        log_info "Archive Count: $archive_count files"
        log_info "Archive Size: $archive_size"
        log_info "========================================="
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "========================================="
    log_info "PostgreSQL Log Rotation and Retention"
    log_info "Environment: $ENVIRONMENT"
    log_info "Retention Period: $RETENTION_DAYS days"
    log_info "========================================="

    # Validate environment
    validate_environment

    # Generate pre-cleanup statistics
    generate_statistics

    # Archive logs (production only)
    if [ "$ENABLE_ARCHIVAL" == "true" ]; then
        archive_logs
    fi

    # Cleanup old logs
    cleanup_old_logs

    # Cleanup old archives (production only)
    if [ "$ENABLE_ARCHIVAL" == "true" ]; then
        cleanup_old_archives
    fi

    # Generate post-cleanup statistics
    generate_statistics

    log_info "Log rotation complete"
    log_info "========================================="
}

# Execute main function
main "$@"

exit 0
