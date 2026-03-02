# Debugging with Toolbx

The Fedora/CentOS bootc image does include some classic systems inspection tools
such as `lsof`, but the recommended approach is to leverage containers
with the [toolbox](https://containertoolbx.org/) utility included in the
image.

> **Note:** Due to an oversight, `toolbox` may not yet be in all images, but it
> should be soon.

## What is Toolbx?

Toolbx is a utility that allows you to create privileged containers
meant to debug and troubleshoot your instance. It is a wrapper around
podman which starts long running containers with default mounts and
namespaces to facilitate debugging the host system.

These containers can then be used to install tools that you may need for
troubleshooting, keeping things distinct from the host root filesystem.

## Using Toolbx

You can create a new toolbox by running the command below.

```sh
toolbox create
```

You can then list all the running toolboxes running on the host. This
should show you your newly created toolbox.

```sh
toolbox list
```

As pointed out by the output of the `toolbox create` command, you can
enter the following command to enter your toolbox.

```sh
toolbox enter
```

Now that you're in the container, you can use the included `dnf` package
manager to install packages. For example, let's install `strace` to look
at read syscall done by the host's `toolbox` utility.

```sh
sudo dnf install strace
# Some hosts directories are mounted at /run/host
strace -eread /run/host/usr/bin/toolbox list
```

Once done with your container, you can exit the container and then
remove it from the host using `toolbox rm` if desired.
