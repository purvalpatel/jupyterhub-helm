Setup Jupyterhub with AMD GPU operator.
---------------------------------------
### Prerequisites.
1. ROCM is installed on server.
2. rocm-smi should list the GPU's.

### Install kubernetes:

#### 1.Swap disable

#### 2.Install tools: (on both master and worker)
```
sudo apt-get update# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet
```

#### 3.Enable IPv4 packet forwarding:
```
cat <<EOF | sudo tee /etc/sysctl.d/k8s.confnet.ipv4.ip_forward = 1
EOF

sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-kubernetes-ip-forward.conf

sudo sysctl --system

sysctl net.ipv4.ip_forward
```

#### 4. Set container runtime for kubernetes:

Ref: https://v1-31.docs.kubernetes.io/docs/setup/production-environment/container-runtimes/

##### Install containerd:(on both master and worker)
```
#sudo apt install -y containerd
```

##### Create default config ( on master and worker )
```
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
```

##### Use systemd as cgroup driver
```
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

##### Restart service
```
sudo systemctl restart containerd
```

#### 4.Initialize master node:
```
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

#### 5.Install CNI plugin:
```
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

### Install helm:
```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```
#### verify the installation: 
`helm version`

### Setup dynamic path provisioner:
This will use to create automatic PVC with pods.

We can change the default location of the storage of this.

```
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
sudo mkdir -p /opt/local-path-provisioner
sudo chmod 0777 /opt/local-path-provisioner

kubectl get all -n jupyter

#If want to change the default storage then,
kubectl edit configmap local-path-config -n local-path-storage

#Set default storage class.
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Setup jupyterhub:

#### Create directory
```
mkdir /mnt/kubernetes/jupyterhub
cd /mnt/kubernetes/jupyterhub
touch config.yaml
```

##### Add repository
```
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update
```

##### Start installation with below command
```
 helm upgrade --cleanup-on-fail \
  --install jhub jupyterhub/jupyterhub \
  --namespace jupyter \
  --create-namespace \
  --version=3.3.7 \
  --values config.yaml
```

##### Note:
In rocm images with jupyterhub there is no rocm driver intalled and due to this pod is showing not ready because gpu is not assigned to pod.


#### Create pvc:
This PVC is used for seperate user wise data and shared folder which we will mount on all users.

Same PVC we will use for both purpose.

shared-pvc.yaml
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jupyter-network-share-pvc
  namespace: jupyter
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-path
```
Apply changes:
```
kubectl apply -f shared-pvc.yaml
```

#### Final config.yaml of jupyterhub deployment

config.yaml
```
hub:
  config:
    JupyterHub:
      authenticator_class: nativeauthenticator.NativeAuthenticator
    Authenticator:
      allowed_users:
        - admin
        - xxxxxxxxx
        - xxxxxx
      admin_users:
        - admin
    NativeAuthenticator:
      enable_signup: true
      enable_change_password: true
      create_users: true
      allow_admin_access: true

  extraConfig:
    native: |
      c.Authenticator.enable_auth_state = True
      c.NativeAuthenticator.enable_password_change = True
      c.Spawner.auth_state_enabled = True

    spawnerForm: |
      # Define available Docker images (must have ROCm to use AMD GPU)
      DOCKER_IMAGES = [
          "docker.merai.app/rocm-notebook:5.7",  # ROCm-enabled notebook
          "jupyter/base-notebook:latest",
          "jupyter/r-notebook:latest",
          "jupyter/scipy-notebook:latest"
      ]

      # Define available AMD GPU IDs
      GPU_IDS = ["none", "0", "1", "2", "0,1", "1,2", "0,1,2", "all"]

      def get_options_form(spawner):
          if not spawner.handler.current_user.name == "admin":
              return ""

          options_html = """
          <div class="form-group">
            <label for="image">Docker Image</label>
            <select name="image" class="form-control" required>
          """
          for image in DOCKER_IMAGES:
              selected = "selected" if image == getattr(spawner, 'image', '') else ""
              options_html += f'<option value="{image}" {selected}>{image}</option>'
          options_html += "</select></div>"

          options_html += """
          <div class="form-group">
            <label for="gpu_id">GPU ID</label>
            <select name="gpu_id" class="form-control">
          """
          for gpu_id in GPU_IDS:
              options_html += f'<option value="{gpu_id}">{gpu_id if gpu_id != "none" else "No GPU"}</option>'
          options_html += "</select></div>"

          options_html += """
          <div class="form-group">
            <label for="cpu_limit">CPU Limit</label>
            <input type="text" name="cpu_limit" class="form-control" value="2" placeholder="Number of CPUs">
          </div>

          <div class="form-group">
            <label for="mem_limit">Memory Limit</label>
            <input type="text" name="mem_limit" class="form-control" value="4G" placeholder="Memory with unit">
          </div>

          <div class="form-group">
            <label for="days_to_live">Days to Live</label>
            <input type="text" name="days_to_live" class="form-control" value="7">
          </div>
          """
          return options_html

      c.Spawner.options_form = get_options_form

      def get_options_from_form(formdata):
          options = {}
          if formdata:
              image = formdata.get('image', [''])[0]
              gpu_id = formdata.get('gpu_id', [''])[0]
              cpu_limit = formdata.get('cpu_limit', ['2'])[0]
              mem_limit = formdata.get('mem_limit', ['4G'])[0]
              days_to_live = formdata.get('days_to_live', ['7'])[0]

              if image:
                  options['image'] = image
              if gpu_id and gpu_id != "none":
                  # Convert GPU selection to AMD resource limits
                  if gpu_id == "all":
                      gpu_count = 3  # you have 3 GPUs
                      options['extra_resource_limits'] = {"amd.com/gpu": str(gpu_count)}
                      options['environment'] = {"ROCR_VISIBLE_DEVICES": "all"}
                  elif "," in gpu_id:
                      gpu_count = len(gpu_id.split(","))
                      options['extra_resource_limits'] = {"amd.com/gpu": str(gpu_count)}
                      options['environment'] = {"ROCR_VISIBLE_DEVICES": gpu_id}
                  else:
                      options['extra_resource_limits'] = {"amd.com/gpu": "1"}
                      options['environment'] = {"ROCR_VISIBLE_DEVICES": gpu_id}

              try:
                  options['cpu_limit'] = float(cpu_limit)
              except ValueError:
                  options['cpu_limit'] = 2.0

              options['mem_limit'] = mem_limit if mem_limit else "4G"
              try:
                  options['days_to_live'] = int(days_to_live)
              except ValueError:
                  options['days_to_live'] = 7

          return options

      c.Spawner.options_from_form = get_options_from_form
      c.JupyterHub.spawner_class = 'kubespawner.KubeSpawner'

      async def apply_user_options(spawner):
          options = getattr(spawner, 'user_options', {})
          if not options:
              return

          if 'image' in options:
              spawner.image = options['image']
          if 'extra_resource_limits' in options:
              spawner.extra_resource_limits = options['extra_resource_limits']
          if 'environment' in options:
              if not hasattr(spawner, 'environment'):
                  spawner.environment = {}
              spawner.environment.update(options['environment'])
          if 'cpu_limit' in options:
              spawner.cpu_limit = float(options['cpu_limit'])
          if 'mem_limit' in options:
              spawner.mem_limit = options['mem_limit']

      c.KubeSpawner.pre_spawn_hook = apply_user_options

singleuser:
  storage:
    type: dynamic
    dynamic:
      storageClass: local-path
    capacity: 100Gi
    homeMountPath: /home/jovyan/work
    extraVolumes:
      - name: network-share
        persistentVolumeClaim:
          claimName: jupyter-network-share-pvc
    extraVolumeMounts:
      - name: network-share
        mountPath: /home/jovyan/shared
        subPath: "Notebook-public"
```

##### Apply changes:
```
helm upgrade --install jhub jupyterhub/jupyterhub   --namespace jupyter   --create-namespace   -f config.yaml
```


Now verify GPU is passed with pod or not.
```
kubectl describe pod jupyter-shishanshu -n jupyter
```

<img width="975" height="491" alt="image" src="https://github.com/user-attachments/assets/4699f96a-64d7-4f51-8cff-c576610f33df" />


##### Expose service to NodePort:
```
kubectl patch svc proxy-public -n jupyter -p '{"spec": {"type": "NodePort"}}'
```


##### Access in browser:

http://<server-ip>:31461/
