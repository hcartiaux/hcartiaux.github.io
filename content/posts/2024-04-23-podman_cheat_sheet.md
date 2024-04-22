---
title: "Podman cheat sheet"
date: 2024-04-20
draft: false
---

This is a cheat sheet of podman useful information and commands.

<!--more-->

Podman is feature equivalent with docker, with the advantage of not requiring root privileges and a daemon running as root.
It can be used alongside with `buildah` to build container images, and `skopeo` to manage container images in a registry.

## Install podman

* Install the package: `apt install podman`
* Allow for unqualified search in the docker.io and quay.io repositories: `echo 'unqualified-search-registries=["docker.io", "quay.io"]' > $HOME/.config/containers/registries.conf`

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

* Create a new container: `podman run -dt <image name>`
* Create a new container and map a directory: `-v <host directory>:<container mount point>`
* Create a new container and map a network port: `-p <host port>:<container port>`
* Enable Auto-update: `--label io.containers.autoupdate=registry`
* Checking for updates: `podman auto-update`
* Enable the auto-update timer: `systemctl --user enable --now podman-auto-update.timer`
* Copy a file to a container: `podman cp <src> <dest>`
* `podman [restart,start,stop,pause,unpause] <CONTAINER ID>`
* Remove a container: `podman rm <CONTAINER ID>`

## Configuration generation

### Kube definition file

* Generate a kube file: `podman generate kube <CONTAINER ID> > <filename>.yaml`
* Import a kube file: `podman play kube <filename>.yaml`

### Systemd units

* Pre-requisites: `systemctl --user enable podman-restart.service`

* Generate a systemd service unit: `podman generate systemd --new <CONTAINER ID> > ~/.config/systemd/user/<CONTAINER NAME>.service`
* Reload systemd: `systemctl --user daemon-reload`
* Enable the container to start at boot: `systemctl --user enable <CONTAINER NAME>.service`

## External Resources

* https://linuxhandbook.com/podman-add-delete-containers/
* https://www.redhat.com/sysadmin/create-containers-podman-quickly
* https://www.redhat.com/sysadmin/container-information-podman
* https://www.redhat.com/sysadmin/update-container-images-podman
* https://developers.redhat.com/blog/2019/01/15/podman-managing-containers-pods
* https://www.redhat.com/sysadmin/podman-auto-updates-rollbacks
* https://linuxhandbook.com/autostart-podman-containers/
