
<h1 align="center">
     Jupyterhub kubernetes setup
    <br>
</h1>

Jupyerhub installation with Kubernetes:
The setup is done through the official documentation - https://z2jh.jupyter.org/en/stable/

Note: This is the research document of jupyterhub setup with helm.

purpose:
-----
This project provides a complete setup of JupyterHub on Kubernetes using Helm, tailored for multi-user environments with resource customization and persistent storage. It includes user management with support for local or external authentication and a dynamic spawner form integrated with KubeSpawner. The spawner form enables configuration of Docker image, GPU device(s), CPU and RAM allocation, and Time-To-Live (TTL) for automatic notebook cleanup. However, resource selection is restricted to admins only—regular users cannot choose or modify resource configurations themselves. Each user's working directory is persistently stored using PVCs (Persistent Volume Claims), ensuring data retention across sessions. This setup is ideal for shared GPU servers or research environments where users need isolated, configurable Jupyter notebook instances on-demand under admin-controlled resource policies.

Project workflow
-------------------------
1. Helm installation
2. Jupyterhub installation with helm chart.
3. Assign GPU to users.
4. Image selection for users at the time of profile creation.
5. Assign CPU,RAM resources.


Helm installation:
------------------
```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

verify the installation: `helm version`

Jupyterhub installation with using helm chart:
----------------------------------------------
1. Create directory
```bash
mkdir /mnt/kubernetes/jupyterhub

cd /mnt/kubernetes/jupyterhub

touch config.yaml
```

2. Add repository
```bash
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update
```

4. Start pods with  below command
```bash
 helm upgrade --cleanup-on-fail \
  --install jhub jupyterhub/jupyterhub \
  --namespace jupyter \
  --create-namespace \
  --version=3.3.7 \
  --values config.yaml
```
Create dynamic provisioning or NFS storage class for PVC.

Here we are creating dynamic storageclass for local path:

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

Then create the PVC storage local path,
```
sudo mkdir -p /opt/local-path-provisioner
sudo chmod 0777 /opt/local-path-provisioner
```
If want to change the local storage path then, change the path:
```
kubectl edit configmap local-path-config -n local-path-storage
```

This will create namespace: jupyter
check this with,
`kubectl get ns`

List all the resources created in jupyter namespace:
```
Kubectl get all -n jupyter
```
If pod is pending and pvc is in pending means pvc is not assigned with storageclass.

Then patch it,
```
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

And delete pod. 

Switch to default jupyter namespace so you dont have to write namespace every time:
`kubectl config set-context --current --namespace=jupyter`

Revert back to default namespace:
`kubectl config set-context --current --namespace=default`

Below are some post installation checks:
Verify that created Pods enter a Running state:
      `kubectl --namespace=jupyter get pod`
      ![instance](https://github.com/purvalpatel/jupyterhub-helm/blob/5be392aad295d7910e289aa34029a9068d4c377c/getpods.png)

    If a pod is stuck with a Pending or ContainerCreating status, diagnose with:
      `kubectl --namespace=jupyter describe pod <name of pod>`

    If a pod keeps restarting, diagnose with:
      `kubectl --namespace=jupyter logs --previous <name of pod>`

  - Verify an external IP is provided for the k8s Service proxy-public.
      `kubectl --namespace=jupyter get service proxy-public`

    If the external ip remains <pending>, diagnose with:
      `kubectl --namespace=jupyter describe service proxy-public`

  - Verify web based access:

    You have not configured a k8s Ingress resource so you need to access the k8s
    Service proxy-public directly.

    If your computer is outside the k8s cluster, you can port-forward traffic to
    the k8s Service proxy-public with kubectl to access it from your
    computer.

      `kubectl --namespace=jupyter port-forward service/proxy-public 8080:http`

    Try insecure HTTP access: `http://localhost:8080`
    
    <img width="570" height="545" alt="image" src="https://github.com/user-attachments/assets/674cbe59-1612-46da-b7e5-eba11f52fefc" />


User Creation:
---------------
When trying to create user for the first time then it will go to pending state.
if face error,
  Type     Reason            Age    From                 Message
  ----     ------            ----   ----                 -------
  Warning  FailedScheduling  2m31s  jhub-user-scheduler  0/1 nodes are available: pod has unbound immediate PersistentVolumeClaims. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.

Then the reason behind this is Dynamic storage volume is not found.
Solution:
Create Dynamic PVC:
`kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml`

Make it default:
```bash
kubectl patch storageclass local-path -p \
  '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

and again upgrade the version:
`helm upgrade jhub jupyterhub/jupyterhub -n jupyter -f config.yaml`

Allow Admin user
----------------
- Here we are using dummy authenticator class(for testing). all users will able to login with the same password.

#config.yaml
```yaml
singleuser:
  storage:
    type: none

hub:
  config:
    JupyterHub:
      authenticator_class: dummy
    DummyAuthenticator:
      password: "admin@123"
  extraConfig:
    allowedUsers: |
      c.Authenticator.allowed_users = {"admin"}
      c.Authenticator.admin_users = {"admin"}
```
upgrade the version:
`helm upgrade --install jhub jupyterhub/jupyterhub   --namespace jupyter   --create-namespace   -f config.yaml`

This is the document of different kind of authenticators: https://jupyterhub.readthedocs.io/en/latest/reference/authenticators.html

If You face error like,
If error while upgrading service:
Error: Get "https://jupyterhub.github.io/helm-chart/jupyterhub-4.2.0.tgz": EOF

Solution:
```bash
helm repo remove jupyterhub
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update
helm upgrade --install jhub jupyterhub/jupyterhub   --namespace jupyter   --create-namespace   -f config.yaml
```

Pass GPU in pod:
--------------------
```yaml
hub:
  config:
    JupyterHub:
      authenticator_class: dummy
    DummyAuthenticator:
      password: "admin@123"
    Authenticator:
      allowed_users:
        - admin
      admin_users:
        - admin

singleuser:
  storage:
    type: none
  extraEnv:
    NVIDIA_VISIBLE_DEVICES: all
    NVIDIA_DRIVER_CAPABILITIES: compute,utility
  extraContainers:
    - name: init-gpu
      image: nvidia/cuda:12.2.0-runtime-ubuntu22.04
      command: [ "sleep", "1" ]
```

Upgrade version:
`helm upgrade --install jhub jupyterhub/jupyterhub   --namespace jupyter   --create-namespace   -f config.yaml`

Pass specific GPU id instead of all GPU:
```yaml
hub:
  config:
    JupyterHub:
      authenticator_class: dummy
    DummyAuthenticator:
      password: "admin@123"
    Authenticator:
      allowed_users:
        - admin
      admin_users:
        - admin

singleuser:
  profileList:
    - display_name: "GPU Server"
      description: "Spawns a notebook server with access to a GPU"
      kubespawner_override:
        extra_resource_limits:
          nvidia.com/gpu: "1"
```
Upgrade version:
`helm upgrade --install jhub jupyterhub/jupyterhub   --namespace jupyter   --create-namespace   -f config.yaml`

Create profiles:
----------------
```yaml
hub:
  config:
    JupyterHub:
      authenticator_class: dummy
    DummyAuthenticator:
      password: "admin@123"
    Authenticator:
      allowed_users:
        - admin
      admin_users:
        - admin

singleuser:
  profileList:
    - display_name: "GPU 0"
      description: "Access to GPU id 0"
      kubespawner_override:
        extra_resource_limits:
          nvidia.com/gpu: "1"
        environment:
          NVIDIA_VISIBLE_DEVICES: "0"
    - display_name: "GPU 1"
      description: "Access to GPU ID 1"
      kubespawner_override:
        extra_resource_limits:
          nvidia.com/gpu: "1"
        environment:
          NVIDIA_VISIBLE_DEVICES: "1"
```
Steps to Create users:
------------
Option 1: (not recommended )
First do add user from admin panel.
Then do signup with that user and change password.

Option 2:
1.Do signup from the login page. And the request of authorization is go to administrator.
Admin can authorize user via - http://127.0.0.1:30235/hub/authorize

2.Now from admin create user again for pod.

admin can change password from here.

http://127.0.0.1:30235/hub/change-password

http://127.0.0.1:30235/hub/change-password/username

Provide different image to different profiles:
--------------------------------------------
[diffprofile.yaml](https://github.com/purvalpatel/jupyterhub-helm/blob/1e3a8d3de3ab98ee80adb62c478aae8597209479/test/diffprofile.yaml)

provide multiple GPUs to profile:
-----------------------------
[multigpu-profiles.yaml](https://github.com/purvalpatel/jupyterhub-helm/blob/9e566bccd05eb75aaffc75bb9653ad9873d3b76c/test/multigpu-profiles.yaml)


Persist data on NFS Storage server:
--------------------------
Create Storage volume which should be expandable.
For that we are using NFS storage.

Get the network storage location which is mounted in server.
Here we are taking wekafs storage mounted on /xxxxx-v1.

1. Create Dynamic Persistent volumes.
2. Setup NFS server On your storage node:
```bash
sudo apt install nfs-kernel-server -y
sudo mkdir -p /m111002-v1/nfs/
sudo chown nobody:nogroup /m111002-v1/nfs/
sudo chmod 777 /m111002-v1/nfs/
```

nano /etc/exports
```
/m111002-v1/nfs/ *(rw,sync,no_subtree_check,no_root_squash)
```

Apply changes:
`sudo exportfs -a`
`sudo systemctl restart nfs-kernel-server`

Install NFS client provider:
`helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/`
```
helm install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=127.0.0.1 \
  --set nfs.path=/m111002-v1/nfs/ \
  --set storageClass.name=nfs-jupyterhub
```

Verify the storageclass:
`kubectl get storageclass`

If wanted to change Reclaim policy then you can change.

Make changes into config.yaml of helm.
#config.yaml
```
  storage:
    type: dynamic
    dynamic:
      storageClass: nfs-jupyterhub
    capacity: 100Gi
    homeMountPath: /home/jovyan/work
```

Remove it which is created previously.

Now Create user and you will see that PV and PVC is created.
```
kubectl get pvc -n jupyter
kubectl get pv -n jupyter
```

Now use this storageclass into our deployment,
config.yaml
```yaml
hub:
  config:
    JupyterHub:
      authenticator_class: nativeauthenticator.NativeAuthenticator
    Authenticator:
      allowed_users:
        - admin
      admin_users:
        - admin
    NativeAuthenticator:
      create_users: true
      allow_admin_access: true
      allow_unauthenticated_users: true


singleuser:
  profileList:
    - display_name: "GPU 0,1"
      description: "Access to GPU id 0,1"
      kubespawner_override:
        image: quay.io/jupyterhub/k8s-singleuser-sample:4.2.0
        extra_resource_limits:
          nvidia.com/gpu: "0"
          nvidia.com/gpu: "1"
        environment:
          NVIDIA_VISIBLE_DEVICES: "0,1"

  storage:
    type: dynamic
    dynamic:
      storageClass: nfs-jupyterhub
    capacity: 100Gi
    homeMountPath: /home/jovyan/work
  initContainers:
    - name: init-gpu
      image: nvidia/cuda:12.2.0-runtime-ubuntu22.04
      command:
        - sleep
        - "1"
```
How to increase size of PVC ?
----------------------
`kubectl edit pvc pvc-9ec25323-19a6-4ce1-a3cd-baa5d89d1151`
Editing this directly wont works.

Increase size in config.yaml.
upgrade version:
`helm upgrade --install --cleanup-on-fail jhub jupyterhub/jupyterhub   --namespace jupyter   --create-namespace   -f config.yaml`

Need to delete and re-created PVC. then it will show the updated size.
Make sure the StorageClass Policy is Retain.

If it is not retain then,
`kubectl get storageclass nfs-jupyterhub -o yaml > sc-nfs-retain.yaml`

Delete the storage class,
`kubectl delete storageclass nfs-jupyterhub`

make changes into sc-nfs-retain.yaml to Retain.
and reapply the changes, `kubectl apply -f sc-nfs-retain.yaml`

Setup of multiple profile selection with custom image:
----------------------
config.yaml
[config.yaml](https://github.com/purvalpatel/jupyterhub-helm/blob/ef5596f32b105fce027667ff47cf65750c7b5b96/test/profile-selection-custom-image.yaml)

start-singleuser.sh
[start-singleuser.sh](https://github.com/purvalpatel/jupyterhub-helm/blob/fa7053bc1b3175409e8d24fc048b31e2a6a939e7/test/start-singleuser.sh)

Dockerfile
[Dockerfile](https://github.com/purvalpatel/jupyterhub-helm/blob/fa7053bc1b3175409e8d24fc048b31e2a6a939e7/test/Dockerfile)

dind-entrypoint.sh
[dind-entrypoint.sh](https://github.com/purvalpatel/jupyterhub-helm/blob/78dc3b84d8c8b193816d066073e3798656c82349/test/dind-entrypoint.sh)


Ask for extra parameters on sign up:
--------------------------------
config.yaml
```yaml
hub:
  config:
    JupyterHub:
      authenticator_class: nativeauthenticator.NativeAuthenticator
    Authenticator:
      allowed_users:
        - admin
      admin_users:
        - admin
    NativeAuthenticator:
      enable_signup: true
      enable_change_password: true
      create_users: true
      allow_admin_access: true
#      allow_unauthenticated_users: true
  extraConfig:
    adminUsers: |
      c.Authenticator.admin_users = {'admin'}
    native: |
      c.Authenticator.enable_auth_state = True
      c.NativeAuthenticator.ask_email_on_signup = True
      c.NativeAuthenticator.enable_password_change = True
```

Upgrade version:
`helm upgrade --install jhub jupyterhub/jupyterhub   --namespace jupyter   --create-namespace   -f config.yaml`


GPU Selection Dropdown:
------------------------
[gpu-selection-dropdown.yaml](https://github.com/purvalpatel/jupyterhub-helm/blob/3d44eec49537069020401fdaa3b125faf4206cdb/test/gpu-selection-dropdown.yaml)

To add R Launcher:
-----------------
```yaml
    - display_name: "GPU 6"
      description: "Access to GPU ID 6"
      slug: "gpu6"
      kubespawner_override:
        image: quay.io/jupyter/r-notebook:2025-07-28
#        image: quay.io/jupyterhub/k8s-singleuser-sample:4.2.0
        extra_resource_limits:
          nvidia.com/gpu: "6"
        environment:
          NVIDIA_VISIBLE_DEVICES: "6"
```
Complete Project with resource selection:
--------------
This project provides a complete setup of JupyterHub on Kubernetes using Helm, tailored for multi-user environments with resource customization and persistent storage. It includes user management with support for local or external authentication and a dynamic spawner form integrated with KubeSpawner. The spawner form enables configuration of Docker image, GPU device(s), CPU and RAM allocation, and Time-To-Live (TTL) for automatic notebook cleanup. However, resource selection is restricted to admins only—regular users cannot choose or modify resource configurations themselves. Each user's working directory is persistently stored using PVCs (Persistent Volume Claims), ensuring data retention across sessions. This setup is ideal for shared GPU servers or research environments where users need isolated, configurable Jupyter notebook instances on-demand under admin-controlled resource policies.

<img width="1001" height="553" alt="image" src="https://github.com/user-attachments/assets/1270b77c-ae91-419f-9301-e8eea0adf39e" />

[config.yaml](https://github.com/purvalpatel/jupyterhub-helm/blob/55abef6c99ad85e26f19a80fe1406e918c2c4766/config.yaml)

Provide shared folder between all users:
--------------------------------------
<img width="753" height="473" alt="image" src="https://github.com/user-attachments/assets/a1035600-41f7-436d-ac8a-7338d2203ecb" />

Create NFS share location:
```bash
mkdir /mnt/notebook-share
echo "/mnt/notebook-share   *(rw,sync,no_subtree_check,no_root_squash,no_all_squash,insecure)" >>/etc/exports

exportfs -ra
sudo systemctl restart nfs-kernel-server
```

Create PV and PVC which is used on shared folder:

shared-pv-pvc.yaml
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jupyter-network-share-pv
spec:
  capacity:
    storage: 1000Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: 10.10.110.22
    path: "/mnt/notebook-share"
  storageClassName: "nfs-jupyterhub"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jupyter-network-share-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1000Gi  # Should match PV size
  storageClassName: "nfs-jupyterhub"  # Must match PV
  volumeName: jupyter-network-share-pv

```
apply changes:
`kubectl apply -f shared-pv-pvc.yaml`

updated config.yaml:
[config.yaml](https://github.com/purvalpatel/jupyterhub-helm/blob/72b08391965b0b85fcf054d29134fa10887936c0/config-shared-folder.yaml)

apply changes:
`helm upgrade --install --cleanup-on-fail jhub jupyterhub/jupyterhub   --namespace jupyter   --create-namespace   -f config.yaml`

Store credentials of docker registry permenantly with containerd:
---------------
nano /etc/containerd/config.tom
```toml
      [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.test.com".auth]
          username = "abc"
          password = "abc1234"

```
restart service:
`systemctl restart containerd`

Now you can pull the images, below is the sample command:
`crictl pull docker.test.com/xxxxxx/jupyterhub-remote-desktop:0.1`

Check user wise resource allocation:
----------------------
`kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\t"}{.spec.containers[0].resources}{"\n"}{end}'`

Store Spawn logs of each users:
--------------------------------

Create pvc for mount log directory:
jupyterhub-spawn-logs-pvc.yaml

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jupyterhub-spawn-logs
  namespace: jupyter
  labels:
    app: jupyterhub
    component: spawn-logs
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-jupyterhub
  resources:
    requests:
      storage: 10Gi

```
Apply changes:

`kubectl apply -f jupyterhub-spawn-logs-pvc.yaml`

Make changes in config.yaml

[store-spawning-logs-config.yaml](https://github.com/purvalpatel/jupyterhub-helm/blob/08f86fa4de7514b2d2d7f0ba053efd6ec2953e24/store-spawning-logs-config.yaml)
