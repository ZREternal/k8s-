#!/bin/bash
#基础配置初始化+kubernetes常见组件kuberadm安装-单节点
#初始化
echo "info 输入IP服务器IP地址"
read MASTER_IP
echo "info 输入需要设置的主机名"
read HOSTNAME
hostnamectl set-hostname $HOSTNAME
#添加DNS
echo $MASTER_IP $HOSTNAME >> /etc/hosts
DNS=`cat /etc/resolv.conf |grep 114`
DNS_LET=${#DNS}
if [[ ${DNS_LET} -eq 0 ]];then
  echo "INFO:添加DNS114.114.114.114"
  echo "nameserver 114.114.114.114 " >> /etc/resolv.conf
else
  echo ""
fi
#修改和添加yum源
yum install -y git wget
wget http://47.109.97.22:81/repo.tar -N
if [ ! -d "repo.tar" ]; then
    wget http://47.109.97.22:81/repo.tar
fi
tar -zxvf repo.tar
rm -rf /etc/yum.repos.d/*
mv repo/* /etc/yum.repos.d/
#安装软件包
yum install -y wget yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo sed -i 's+download.docker.com+mirrors.tuna.tsinghua.edu.cn/docker-ce+' /etc/yum.repos.d/docker-ce.repo

sudo yum install -y epel-release
sudo yum install -y conntrack ipvsadm ipset jq sysstat curl iptables libseccomp

# 调整系统 TimeZone
sudo timedatectl set-timezone Asia/Shanghai

# 将当前的 UTC 时间写入硬件时钟
sudo timedatectl set-local-rtc 0

# 重启依赖于系统时间的服务
sudo systemctl restart rsyslog
sudo systemctl restart crond

#设置系统参数
cat > kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
EOF
sudo cp kubernetes.conf  /etc/sysctl.d/kubernetes.conf
sudo sysctl -p /etc/sysctl.d/kubernetes.conf
sudo mount -t cgroup -o cpu,cpuacct none /sys/fs/cgroup/cpu,cpuacct

#加载内核模块
sudo modprobe br_netfilter
sudo modprobe ip_vs
#基础设置
#关闭防火墙
systemctl stop firewalld  && systemctl  disable  firewalld

#关闭swap分区
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

#关闭selinux
sed -i  's/SELINUX=enforcing/SELINUX=disabled/'  /etc/sysconfig/selinux
sed -i  's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

#时间同步
yum install ntpdate -y
ntpdate cn.pool.ntp.org
service crond restart
chronyc sources -v
#开启ipvs
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
ipvs_modules="ip_vs ip_vs_lc ip_vs_wlc ip_vs_rr ip_vs_wrr ip_vs_lblc ip_vs_lblcr ip_vs_dh ip_vs_sh ip_vs_nq ip_vs_sed ip_vs_ftp nf_conntrack"
for kernel_module in ${ipvs_modules}; do
 /sbin/modinfo -F filename ${kernel_module} > /dev/null 2>&1
 if [ 0 -eq 0 ]; then
 /sbin/modprobe ${kernel_module}
 fi
done
EOF

chmod 755 /etc/sysconfig/modules/ipvs.modules && bash  /etc/sysconfig/modules/ipvs.modules && lsmod | grep ip_vs

#docker
yum install docker-ce docker-ce-cli  containerd.io -y

sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://3ri333r1.mirror.aliyuncs.com","https://dockerhub.azk8s.cn","http://hub-mirror.c.163.com"],
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker


#containerd配置
containerd config default > /etc/containerd/config.toml
#配置 systemd cgroup 驱动

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
#覆盖沙盒 (pause) 镜像
sed -i "s#registry.k8s.io/pause#registry.aliyuncs.com/google_containers/pause#g" /etc/containerd/config.toml
echo 'endpoint = ["https://registry.cn-hangzhou.aliyuncs.com" ,"https://registry-1.docker.io"]' >> /etc/containerd/config.toml
#重启containerd
systemctl daemon-reload
systemctl enable --now containerd
systemctl restart containerd
# 安装crictl工具
yum install -y cri-tools
# 生成配置文件
crictl config runtime-endpoint
# 编辑配置文件
cat << EOF | tee /etc/crictl.yaml
runtime-endpoint: "unix:///run/containerd/containerd.sock"
image-endpoint: "unix:///run/containerd/containerd.sock"
timeout: 10
debug: false
pull-image-on-create: false
disable-pull-on-run: false
EOF
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet && systemctl start kubelet
mkdir -p /etc/kubernetes/pki/etcd &&mkdir -p ~/.kube/
#安装kubernetes
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet && systemctl start kubelet

kubeadm init --apiserver-advertise-address=$MASTER_IP \
             --pod-network-cidr=192.168.0.0/16 \
             --service-cidr=10.96.0.0/12 \
             --image-repository registry.aliyuncs.com/google_containers  >> ./join.txt

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#By default, for security reasons, the cluster will not schedule pods on the master node. If you want to be able to schedule pods on the master node, please run:
#kubectl taint nodes --all node-role.kubernetes.io/control-plane- node-role.kubernetes.io/master-
kubectl taint nodes --all node-role.kubernetes.io/control-plane- node-role.kubernetes.io/master-
wget http://47.109.97.22:81/yaml/custom-resources.yaml --no-check-certificate -N
wget http://47.109.97.22:81/yaml/tigera-operator.yaml --no-check-certificate -N
if [ ! -d "tigera-operator.yaml" ]; then
wget http://47.109.97.22:81/yaml/custom-resources.yaml --no-check-certificate -N
fi
if [ ! -d "custom-resources.yaml" ]; then
wget http://47.109.97.22:81/yaml/tigera-operator.yaml --no-check-certificate -N
fi
kubectl create -f tigera-operator.yaml
kubectl create -f custom-resources.yaml
## 注意，如果你init配置的是 --pod-network-cidr=192.168.0.0/16，那就不用改，直接运行即可，否则你需要把文件先下下来来，改成你配置的，在创建
##kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml
kubeadm token create --print-join-command >>masterjoin.txt
