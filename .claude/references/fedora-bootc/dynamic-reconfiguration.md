# Dynamic Reconfiguration

The bootc model emphasises building a custom container image, binding
together a base operating system with configuration in a "static"
manner.

However, there are no default restrictions on "dynamic"
reconfiguration. For example, you can include default firewall rules in
the base image configuration, but it's also possible to directly apply
live firewalling changes by invoking tools such as `nft` or
`firewall-cmd` etc. by invoking the command directly, or scripting it
across multiple machines via tooling such as
[Ansible](https://www.ansible.com).

## Best practice: transient runtime reconfiguration

Using firewalling as an example, the default for the
[firewall-cmd](https://firewalld.org/documentation/man-pages/firewall-cmd.html)
tool is that changes are **not** persistent across a reboot; you need to
explicitly use the `--permanent` flag, which will cause the changes to
be written to the `/etc` directory.

By default, the `/etc` directory is persistent, and changes made via
tools such as `firewall-cmd --permanent` can over time lead to "state
drift"; the contents of the `/etc` on the system will differ from the
one described in the container image. In this default configuration, a
best practice is to first make the changes in the base image, queuing
the changes (but not restarting running systems), and also
simultaneously write e.g. an Ansible playbook to apply the changes to
existing systems, but just in memory.

> **Note:** It is also possible to configure the `/etc` directory to be transient
> as well. For more, see [Filesystem](https://docs.fedoraproject.org/en-US/bootc/filesystem/).

## The `/run` directory

The `/run` directory is an [API
filesystem](https://www.freedesktop.org/wiki/Software/systemd/APIFileSystems/)
that is defined to be deleted when the system is restarted. It is a best
practice to use this directory for transient files.

## Dynamic reconfiguration models

### Pull

A common pattern is to contact a remote network server for dynamic
configuration state. This is effectively how
[Kubernetes](https://kubernetes.io/) operates - the API server defines
the desired state of the system, and machines reconcile to that state.

In this model, you may either include code directly embedded in your
base image or a privileged container that contacts the remote network
server for configuration, and itself spawns further container images
(for example, via the [podman
API](https://docs.podman.io/en/latest/_static/api.html)).

### Push

Instead of a "pull" based model, at least some workloads may best
match a "push" model, as implemented by tooling such as
[Ansible](https://www.ansible.com/).

## Example subsystems and tools

### systemd

For systemd units, there is full support for dynamic transient
reconfiguration or launching new services by writing to the
`/run/systemd` directory. For example, `systemctl edit --runtime
foo.service` will allow dynamically changing the configuration of the
`foo.service` unit, without persisting the changes.

### NetworkManager

There is a `/run/NetworkManager/conf.d` directory for applying temporary
network configuration.

The `nmcli connection modify` command by default writes persistent
changes; there is a `--temporary` flag that can be used to make changes
only in memory.

### podman

The default for `podman run` is to create a container that will
persist across system reboots. The `--rm` flag can be used for transient
containers. For more on this, see [Running containers](https://docs.fedoraproject.org/en-US/bootc/running-containers/) as well as the
[Podman documentation](https://podman.io/).

## Injecting code dynamically

In many cases of dynamic reconfiguration, a tool may want to execute
code on the host filesystem, perhaps copying it over SSH - for example,
Ansible does this.

But even "systems management" agents that run as a container may still
have a need to execute code.

Often some of these tools need to handle a diverse set of operating
systems.

The recommendation is to place this dynamic code in `/tmp` by default. A
benefit of this location is that it's clear that the code is only
temporary and should go away on reboot. Some systems may attempt
"hardening" by making `/tmp` be mounted `noexec`, but that's always
been trivial to bypass by writing a file and then pointing the
interpreter at it (e.g. `/bin/bash /tmp/myfile` instead of just
executing `/tmp/myfile`).

Specifically placing it in e.g. `/root` may cause it to persist across
reboots, which is commonly not desired.
