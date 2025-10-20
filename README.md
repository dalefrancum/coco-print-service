# CoCo Print Service

A systemd service that monitors a directory for new text files from CoCo DriveWire, automatically prints them via CUPS, and archives them with timestamps.

**Note:** Throughout this documentation, `/cocoprints` is used as the example monitoring directory. However this path is fully configurable via the `MONITOR_DIR` setting in the configuration file.

## Installation

### 1. Install Dependencies

```bash
# On Ubuntu/Debian
sudo apt update
sudo apt install inotify-tools cups-client

# On RHEL/CentOS/Fedora
sudo dnf install inotify-tools cups-client
# or
sudo yum install inotify-tools cups-client
```

### 2. Create Service User

```bash
sudo useradd --system --no-create-home drivewire
```

**Note:** The service runs as user `drivewire` with group `drivewire` by default. You may want to customize this by editing the `User=` and `Group=` lines in `coco-print-service.service`

### 3. Install Files

```bash
# Copy the service script
sudo cp coco-print-service.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/coco-print-service.sh

# Copy the configuration file
sudo cp coco-print-service.conf /etc/

# Copy the systemd service file
sudo cp coco-print-service.service /etc/systemd/system/
```

### 4. Create and Configure Directories

**Important:** The service requires the monitoring directory and archive subdirectory to be created before starting.

```bash
# Create the monitoring directory and archive subdirectory
sudo mkdir -p /cocoprints/archive

# Set appropriate permissions
sudo chown -R drivewire:drivewire /cocoprints
sudo chmod -R 2755 /cocoprints
```

**Note:** If you change `MONITOR_DIR` in the configuration, make sure to create that directory and its `archive` subdirectory with appropriate permissions.

### 5. Configure the Service

Edit the configuration file: `/etc/coco-print-service.conf`

Key settings:
- `MONITOR_DIR`: Directory to monitor (default: `/cocoprints`)
- `PRINTER_NAME`: CUPS printer name (default: `default`)
- `LOG_LEVEL`: Logging verbosity (`DEBUG`, `INFO`, `WARN`, `ERROR`)

### 6. Enable and Start the Service

```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Enable the service to start at boot
sudo systemctl enable coco-print-service

# Start the service
sudo systemctl start coco-print-service

# Check status
sudo systemctl status coco-print-service
```

## Usage

### Finding Available Printers

```bash
lpstat -p
```

### Testing the Service

1. Ensure the service is running:
   ```bash
   sudo systemctl status coco-print-service
   ```

2. Place a test file in the monitored directory:
   ```bash
   echo "Test print from CoCo" > /cocoprints/test.txt
   ```

3. Check the logs:
   ```bash
   # System logs
   sudo journalctl -u coco-print-service -f

   # Service logs
   tail -f /cocoprints/coco-print.log
   ```

### Monitoring Logs

```bash
# Follow system logs
sudo journalctl -u coco-print-service -f

# Follow service logs
sudo tail -f /cocoprints/coco-print.log

# View recent activity
sudo journalctl -u coco-print-service --since "1 hour ago"
```

## File Processing Flow

1. **Detection**: Service detects new `.txt` file in monitored directory
2. **Rename**: File is renamed with timestamp (e.g., `printjob.txt` → `printjob_20241019143022.txt`)
3. **Print**: File is sent to CUPS printer using `lp` command
4. **Archive**: File is moved to `archive/` subdirectory

## Troubleshooting

### Service Won't Start

1. Check service status:
   ```bash
   sudo systemctl status coco-print-service
   ```

2. Check dependencies:
   ```bash
   which inotifywait
   which lpstat
   which lp
   ```

3. Verify directories exist and check permissions:
   ```bash
   ls -ld /cocoprints /cocoprints/archive
   ```
   If directories don't exist, create them as shown in Installation step 4.

### Files Not Being Processed

1. Check if service is monitoring:
   ```bash
   sudo journalctl -u coco-print-service -f
   ```

2. Verify file patterns match (must be `.txt` files by default)

3. Ensure files aren't being created in `archive/` subdirectory

### Printing Issues

1. Check printer status:
   ```bash
   lpstat -p
   ```

2. Check CUPS service:
   ```bash
   sudo systemctl status cups
   ```

3. Test manual printing:
   ```bash
   echo "test" | lp -d your-printer-name
   ```

### Log File Issues

Check log file permissions and directory access:
```bash
sudo ls -la /cocoprints/
sudo tail /cocoprints/coco-print.log
```

## Uninstall

```bash
# Stop and disable service
sudo systemctl stop coco-print-service
sudo systemctl disable coco-print-service

# Remove files
sudo rm /etc/systemd/system/coco-print-service.service
sudo rm /usr/local/bin/coco-print-service.sh
sudo rm /etc/coco-print-service.conf

# Reload systemd
sudo systemctl daemon-reload

# Remove service user (optional)
sudo userdel coco-print

# Remove monitoring directory (optional)
sudo rm -rf /cocoprints
```

## License

This project is released into the public domain.

## Contributing

Feel free to submit issues, feature requests, or pull requests.
