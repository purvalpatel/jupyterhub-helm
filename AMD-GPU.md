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
