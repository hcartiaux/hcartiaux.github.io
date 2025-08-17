---
title: "Podman cheat sheet"
date: 2024-04-20
draft: false
toc: true
tags: [linux, sysadmin, containers]
---

This is a cheat sheet of podman useful information and commands (updated in August 2025).

<!--more-->

Podman is feature equivalent with docker, with the advantage of not requiring root privileges and a daemon running as root.
It's also well integrated with `systemd`.
Podman can be used alongside with `buildah` to build container images, and `skopeo` to manage container images in a registry.

## Install podman

* Install the package: `apt install podman`
* Allow for unqualified search in the docker.io and quay.io repositories: `echo 'unqualified-search-registries=["docker.io", "quay.io"]' > $HOME/.config/containers/registries.conf`
* Enable the auto-update timer: `systemctl [--user] enable --now podman-auto-update.timer`

## Image management

* List pulled images: `podman image ls`
* Show the history of an image: `podman image history <image name>`
* Retrieve or update an image: `podman image pull <image name>`
  Do not forget to restart the containers using this image to use the updated version.
* Retrieve a specific image version: `podman pull <image name>:<version|latest>`

## Get information about running containers

* List running containers: `podman ps`
* List all containers: `podman ps -a`
* Sort all containers by size: `podman ps --size --sort size`
* Sort all containers by creation time: `podman ps --sort created`
* List with a customized format: `podman ps --all --format "{{.Names}} {{.Ports}} {{.Mounts}} {{.Status}}"`
* Live resource information by container: `podman stats`

## Control a container

* Create a new container and detach it: `podman run -dt <image name>`
* Create a new container and get an interactive shell: `podman run -it <image name>`
* Create a new container and map a directory: `-v <host directory>:<container mount point>`
* Create a new container and map a network port: `-p <host port>:<container port>`
* Enable Auto-update: `--label io.containers.autoupdate=registry`
* Checking for updates: `podman auto-update`
* Copy a file to a container: `podman cp <src> <dest>`
* Get an interactive shell inside a running container: `podman exec -it <CONTAINER ID> /bin/bash`
* `podman [restart,start,stop,pause,unpause] <CONTAINER ID>`
* Remove a container: `podman rm <CONTAINER ID>`

## Configuration generation

### Kube definition file

* Generate a kube file: `podman generate kube <CONTAINER ID> > <filename>.yaml`
* Import a kube file: `podman play kube <filename>.yaml`

### Compose

Podman is compatible with `docker compose`, install the package named `podman-compose` and create a file named `compose.yaml`, as an example:

```
services:
  intel-llm:
    image: docker.io/intelanalytics/ipex-llm-inference-cpp-xpu:latest
    container_name: intel-llm
    devices:
      - /dev/dri
    volumes:
      - intel-llm:/root/.ollama/models
    ports:
      - "127.0.0.1:11434:11434"
    environment:
      - HOSTNAME=intel-llm
      - no_proxy=localhost,127.0.0.1
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_NUM_GPU=999
      - ZES_ENABLE_SYSMAN=1
      - OLLAMA_INTEL_GPU=true
    restart: unless-stopped
    command: sh -c 'mkdir -p /llm/ollama && cd /llm/ollama && init-ollama && exec ./ollama serve'

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    volumes:
      - open-webui:/app/backend/data
    ports:
      - "127.0.0.1:3000:8080"
    environment:
      - OLLAMA_BASE_URL=http://intel-llm:11434
      - WEBUI_AUTH=False
    restart: unless-stopped

volumes:
  intel-llm:
  open-webui:
```

In the same directory:

* Start all containers, and detach: `podman compose up -d`
* Stop all containers: `podman compose down`
* Start or stop individual services: `podman compose [start|stop]`
* List all running containers: `podman compose ps`
* Get the last logs of the containers: `podman compose logs -f`

### Quadlet

Configuration directories:

* `/usr/share/containers/systemd/`
* `/etc/containers/systemd/`
* `~/.config/containers/systemd` (*rootless*)

Create a container file:

```
[Unit]
Description=HTTPD server
After=local-fs.target

[Container]
Image=docker.io/library/httpd:latest
AutoUpdate=registry
#Exec=sleep 1000
PublishPort=8080:80 # Port mapping
Volume=%h/public:/var/www/ # %h is mapped to the user home dir
Environment=ENV=prod # Environment variable

[Install]
# Start by default on boot
WantedBy=multi-user.target default.target
```

Before podman version 5.6.0, and copy the file manually in `.config/containers/systemd/httpd.container`.
Starting podman version 5.6.0, do not edit `~/.config/containers/systemd` manually, use [`podman quadlet`](https://docs.podman.io/en/latest/markdown/podman-quadlet.1.html) to manage the quadlet files:

* Install a quadlet file: `podman quadlet install httpd.container`
* Remove a quadlet file: `podman quadlet rm httpd.container`
* Print the content of a quadlet file: `podman quadlet print httpd.container` or `systemctl [--user] cat <quadlet name>`
* List installed quadlets: `podman quadlet list`

Manage the quadlet as a systemd service:

* Reload and scan for local changes: `systemctl [--user] daemon-reload`
* Validate the quadlet files: `/usr/lib/podman/quadlet -dryrun --user`
* Start the container: `systemctl [--user] start <quadlet name>`
* Enable and start the container: `systemctl [--user] enable --now <quadlet name>`

## Clean-up

Clean-up the system of unused files (use with caution): `podman system prune -a [--volumes]`

## External Resources

* https://linuxhandbook.com/podman-add-delete-containers/
* https://www.redhat.com/sysadmin/create-containers-podman-quickly
* https://www.redhat.com/sysadmin/container-information-podman
* https://www.redhat.com/sysadmin/update-container-images-podman
* https://developers.redhat.com/blog/2019/01/15/podman-managing-containers-pods
* https://www.redhat.com/sysadmin/podman-auto-updates-rollbacks
* https://linuxhandbook.com/autostart-podman-containers/
* https://mo8it.com/blog/quadlet/
* https://linuxconfig.org/how-to-run-podman-containers-under-systemd-with-quadlet
* https://wiki.archlinux.org/title/Podman
