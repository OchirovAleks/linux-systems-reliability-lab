# Linux Systems & Reliability Lab

A hands-on lab for learning Linux, systemd, failure diagnostics, and service monitoring.

## Current Architecture

Browser on Mac
→ HTTP port 8080
→ reliability-web.service
→ Python HTTP server
→ index.html

reliability-health.timer
→ every 30 seconds
→ reliability-health.service
→ check-health.sh
→ HTTP health check

## Components

- `scripts/install.sh` — installs the application and systemd units.
- `index.html` — test web page.
- `check-health.sh` — service availability check.
- `systemd/reliability-web.service` — web service management.
- `systemd/reliability-health.service` — one-shot health check.
- `systemd/reliability-health.timer` — periodic health-check scheduler.
- `docs/runbooks/` — diagnostic and recovery procedures.

## Installation

Clone the repository:

    git clone git@github.com:OchirovAleks/linux-systems-reliability-lab.git
    cd linux-systems-reliability-lab

Install the application and systemd units:

    sudo ./scripts/install.sh

The installer:

- creates the dedicated `reliability-web` system user;
- installs the application into `/opt/reliability-web`;
- installs the systemd units;
- enables and starts the web service and health-check timer.

## Service Operations

Start the service:

    sudo systemctl start reliability-web

Stop the service:

    sudo systemctl stop reliability-web

Check service status:

    systemctl status reliability-web --no-pager

Read service logs:

    journalctl -u reliability-web -n 20 --no-pager

Run the health check:

    sudo -u reliability-web /opt/reliability-web/check-health.sh

## Reliability Behavior

- The service starts automatically after a reboot.
- systemd restarts the process after an unexpected failure.
- The health check runs every 30 seconds.
- `UP` and `DOWN` results are stored in the systemd journal.

## Current Limitations

- The service and its monitoring run inside the same VM.
- If the entire VM fails, the internal monitor also stops.
- Metrics, dashboards, and external notifications are not implemented yet.
