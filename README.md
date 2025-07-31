
<h1 align="center">
     Jupyterhub Helm
    <br>
</h1>

Jupyerhub installation with Kubernetes:
The setup is done through the official documentation - https://z2jh.jupyter.org/en/stable/

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


This will create namespace: jupyter
check this with,
`kubectl get ns`

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

