#!/bin/bash
#修改kube-proxy为ipvs
output=$(kubectl get cm -n kube-system kube-proxy -o yaml|grep mode)
if [[ "$output" == *"mode: \"\""* ]]; then
  echo "Updating kube-proxy configuration to use IPVS mode"
  kubectl get cm -n kube-system kube-proxy -o yaml | sed "s/mode: \"\"/mode: ipvs/" | kubectl replace -f -
  kubectl delete pod -n kube-system -l k8s-app=kube-proxy
else
  echo "kube-proxy is already using IPVS mode"
fi
