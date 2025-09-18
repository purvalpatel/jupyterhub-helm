```
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
    type: dynamic
    dynamic:
      storageClass: local-path
    capacity: 10Gi
    homeMountPath: /home/jovyan/work
  extraEnv:
    ROCR_VISIBLE_DEVICES: all          # AMD GPU(s)
    ROCM_DEVICE_VISIBLE_DEVICES: all   # optional, depending on plugin version
  extraContainers:
    - name: init-gpu
      image: rocm/rocm-terminal:5.7     # ROCm base image
      command: [ "sleep", "1" ]
```
Apply changes.
```
 helm upgrade --install jhub jupyterhub/jupyterhub   --namespace jupyter   --create-namespace   -f config.yaml
```

Specific GPU pass:
```
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
    type: dynamic
    dynamic:
      storageClass: local-path
    capacity: 10Gi
    homeMountPath: /home/jovyan/work

  extraEnv:
    ROCR_VISIBLE_DEVICES: "1"          # Select AMD GPU 1
    ROCM_DEVICE_VISIBLE_DEVICES: "1"   # Optional, depending on ROCm plugin version

  extraContainers:
    - name: init-gpu
      image: rocm/rocm-terminal:5.7   # ROCm base image
      command: ["sleep", "1"]
```
### Note:
In rocm images with jupyterhub there is no rocm driver intalled and due to this pod is showing not ready because gpu is not assigned to pod.
