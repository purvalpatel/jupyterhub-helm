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


Create pvc:
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


config.yaml
```
hub:
  config:
    JupyterHub:
      authenticator_class: nativeauthenticator.NativeAuthenticator
    Authenticator:
      allowed_users:
        - admin
        - shishanshu
        - nishant
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
