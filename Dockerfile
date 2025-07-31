FROM nvidia/cuda:12.6.2-cudnn-devel-ubuntu22.04

# Install Docker and necessary packages
RUN apt-get update && \
    apt-get install -y openssh-server sudo curl wget  wget screen git supervisor iptables nano tmux && \
    mkdir /var/run/sshd

# Create a new user 'jovyan' with password 'jovyan' and add to sudo and docker groups
RUN useradd -m -s /bin/bash jovyan &&  echo 'jovyan:jovyan' | chpasswd &&  usermod -aG sudo jovyan
RUN apt update && apt install -y python3 python3-pip && \
    pip3 install notebook jupyterhub jupyterlab

RUN mkdir /etc/work
RUN mkdir /etc/jupyterhub-singleuser
RUN chmod 0777 /etc/jupyterhub-singleuser

RUN echo 'jovyan ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
WORKDIR /home/jovyan

ENV DOCKER_TLS_CERTDIR=/certs
RUN mkdir /certs /certs/client && chmod 1777 /certs /certs/client

COPY start-singleuser.sh /usr/local/bin/start-singleuser.sh
COPY dind-entrypoint.sh /usr/local/bin/dind-entrypoint.sh

RUN chmod +x /usr/local/bin/start-singleuser.sh
RUN chmod +x /usr/local/bin/dind-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/start-singleuser.sh"]

EXPOSE 8888
