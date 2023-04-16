#!/bin/bash
wget http://47.109.97.22:81/yaml/components.yaml --no-check-certificate -N
sed -i 's/k8s.gcr.io\/metrics-server\/metrics-server/registry.aliyuncs.com\/google_containers\/metrics-server/g' components.yaml
if grep -q "kubelet-insecure-tls" components.yaml; then
echo "已有该内容，无需修改"
else
sed -i '/- --metric-resolution=15s/a \        - --kubelet-insecure-tls' components.yaml
fi
kubectl apply -f components.yaml
kubectl top nodes
