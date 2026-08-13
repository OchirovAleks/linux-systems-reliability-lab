# Runbook: Reliability Web Service Down

## Trigger

Use this runbook when:

- the health check reports `DOWN`;
- HTTP requests to port 8080 fail;
- `reliability-web.service` is inactive or failed.

## User Impact

The lab web page is unavailable from the browser and HTTP clients.

## Initial Checks

Check whether the service is active:

    systemctl is-active reliability-web

Run the application health check:

    sudo -u reliability-web /opt/reliability-web/check-health.sh

Check whether port 8080 is listening:

    ss -ltnp | grep ':8080'

## Diagnosis

Inspect the service status:

    systemctl status reliability-web --no-pager

Read the latest service logs:

    journalctl -u reliability-web -n 30 --no-pager

Check for failed systemd units:

    systemctl --failed --no-pager

Check available disk space:

    df -h /

Check available memory:

    free -h

## Recovery

If the service is inactive, start it:

    sudo systemctl start reliability-web

If the service is active but unhealthy, restart it:

    sudo systemctl restart reliability-web

## Verification

Confirm that the service is active:

    systemctl is-active reliability-web

Run the health check:

    sudo -u reliability-web /opt/reliability-web/check-health.sh

Verify the HTTP response:

    curl -I http://127.0.0.1:8080/

Expected results:

- service state: `active`;
- health-check output: `UP`;
- health-check exit code: `0`;
- HTTP status: `200 OK`.

## Escalation

If recovery fails, collect the following evidence:

    systemctl status reliability-web --no-pager
    journalctl -u reliability-web -n 100 --no-pager
    systemctl --failed --no-pager
    df -h /
    free -h
    ss -ltnp

Do not repeatedly restart the service without reviewing its logs.
