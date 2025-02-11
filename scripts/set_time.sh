#!/bin/bash

echo "Stopping ntpsec service..."
systemctl stop ntpsec.service
sleep 5

echo "Attmping to sync time..."
ntpd -qg
sleep 5

echo "Starting ntpsec service..."
systemctl start ntpsec.service
sleep 5
ntpq -p
