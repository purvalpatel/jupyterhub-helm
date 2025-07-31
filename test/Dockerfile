FROM nvidia/cuda:12.6.2-cudnn-devel-ubuntu22.04

# Install Docker and necessary packages
RUN apt-get update && \
    apt-get install -y docker.io openssh-server sudo curl wget  wget screen git supervisor iptables nano tmux && \
    mkdir /var/run/sshd

# Configure SSH (set a root password and allow root login)
RUN echo 'root:toor@1337' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

# Create a new user 'ak57102v' with password 'ak57102v' and add to sudo and docker groups
RUN useradd -m -s /bin/bash jovyan &&  echo 'jovyan:I@m1337' | chpasswd &&  usermod -aG sudo,docker jovyan
RUN apt update && apt install -y python3 python3-pip && \
    pip3 install notebook jupyterhub jupyterlab

RUN mkdir /etc/work
RUN mkdir /etc/jupyterhub-singleuser
RUN chmod 0777 /etc/jupyterhub-singleuser

RUN echo 'jovyan ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
# Set the working directory to /home/christian
WORKDIR /home/jovyan

# Enable DinD
ENV DOCKER_TLS_CERTDIR=/certs
RUN mkdir /certs /certs/client && chmod 1777 /certs /certs/client

# Install Docker Compose
RUN curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/bin/docker-compose && \
    chmod +x /usr/bin/docker-compose

# Entrypoint script to start SSH and Docker daemon
COPY start-singleuser.sh /usr/local/bin/start-singleuser.sh
COPY dind-entrypoint.sh /usr/local/bin/dind-entrypoint.sh

RUN chmod +x /usr/local/bin/start-singleuser.sh
RUN chmod +x /usr/local/bin/dind-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/start-singleuser.sh"]

# Expose SSH and Docker daemon ports
EXPOSE 8888
