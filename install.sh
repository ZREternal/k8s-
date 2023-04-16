#!/bin/bash
sh install-k8s.sh
sleep 10
sh ipvs.sh
sleep 10
sh metrics.sh
