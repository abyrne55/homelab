# Building Containers

The original Docker container model of using "layers" to model
applications has been extremely successful. This project aims to apply
the same technique for bootable host systems - using standard OCI/Docker
containers as a transport and delivery format for base operating system
updates.

With bootable containers, you can build and customize the entire host OS
with the same tools as for application containers. That means you can
build on top of base bootc images with Dockerfiles and tailor the OS to
your needs.

## Container-Build Environment

It is crucial to understand that a container-build environment has
certain limitations that impact the commands we can run in a
Containerfile.

The kernel, for instance, is shared with the one of the host
environment. Hence, changes to kernel tunables (sysctl) should be made
in the form of configuration files as explained in the
[system-configuration docs](https://docs.fedoraproject.org/en-US/bootc/sysctl/).

You may find solutions in our [examples
repository](https://gitlab.com/fedora/bootc/examples).

## Configuration tools using D-Bus and other IPC

Some projects like firewalld include CLI configuration tools (e.g.,
`firewall-cmd`) that default to assuming they are part of a running
system. However, in a container build environment the daemon is not
running, and these commands may fail. There is no one-size-fits-all
solution to commands failing due to missing D-Bus. In many cases, the
commands are used to configure the system which can also be done via
configuration files.

Let's take a look at the following two examples:

- `firewall-cmd` depends on D-Bus and will fail when being executed in a
  Containerfile. However, we can use the `firewall-offline-cmd` which is
  built for exactly such use-cases where the firewalld daemon is not
  running.

- `tuned` is a profile-based power-management daemon that is usually
  being controled with the `tuned-adm` client that communicates over
  D-Bus. In this case, we can revert to configuring `tuned` via its
  configuration files in `/etc/tuned`. For instance, the active profile
  can be written to `/etc/tuned/active_profile` instead of running
  `tuned-adm profile <profile>`.

## systemd

systemd is not running in a standard container-build environment. Hence,
certain commands that expect a running system daemon may not work as
expected and error out. Starting a systemd service via `systemctl start`,
for instance, will not work. Configuring a service to start at
boot time via `systemctl enable`, however, works.

## Deferring to systemd services

Commands used to configure the system can usually be replaced by writing
to the individual configuration files. However, if you run into a
situation where a command must be executed on an installed Linux system,
using a [systemd
service](https://docs.fedoraproject.org/en-US/quick-docs/systemd-understanding-and-administering/#_creating_new_systemd_service)
that fires at system runtime (e.g., during boot) may the right approach.

Let's assume that an exemplary `/usr/bin/important-cmd` does not run
correctly due limitations of the container-build environment. We can
move executing this command into a systemd service that fires at boot
time:

### important-cmd.service

```text
[Unit]
Description=Run important-cmd at runtime instead of build time.
[Service]
Type=simple
ExecStart=/usr/bin/important-cmd
[Install]
WantedBy=multi-user.target
```

The systemd service can be copied to
`/usr/lib/systemd/system/important-cmd.service` in the Containerfile
where a `RUN systemctl enable important-cmd.service` would
instruct it to be started at boot once the network is available.

## Best Practices

## Multi-stage builds

Bootc containers are shipped as ordinary OCI containers and are intended
to be usable as part of a container build process, but are primarily
designed to run on booted physical/virtual machines via bootc. Hence,
there is a number of things to consider when building and running bootc
OCI containers.

There is a number of systemd services that setup the filesystem, among
other things. For instance, the root's home directory is not present but
created by a systemd service on boot/init. That implies that a bootc
container is not always the best environment to, for instance, compile a
project. We recommend [multi-stage
builds](https://docs.docker.com/build/building/multi-stage/) for that
purpose and compile the source in a build stage from which build
artifacts can be copied into the final stage to create a derived image.

## dnf -y update

Do **not** attempt to invoke `dnf -y update` (or `upgrade`) in
general. While some things will work correctly, others will not
(especially at the moment kernel and bootloader updates). We will aim to
fix much of this over time, but still you should instead prefer only
explicitly pulling in updates (or reversions) that you need.

The secondary reason to avoid this: Often people choose image-based
updates for their predicability, and you can easily "pin" the base
image by digest for example. The default for dnf repositories is to
"float" - so what happens with an image build today could be different
tomorrow. Packages can be locked with extra effort.

If you want to make large scale changes to the base image, instead look
at using the [from scratch build](https://docs.fedoraproject.org/en-US/bootc/building-from-scratch/).

## linting

We recommend running the `bootc container lint` command as a final
stage during a container build in Containerfile. This command will
perform a number of checks inside the container image and throw an error
in case of issues.

### Containerfile

```dockerfile
FROM quay.io/fedora/fedora-bootc:42
# Customization steps
RUN bootc container lint
```

## Kernel management

On recent images we introduced kernel-install integration which allows
you to use DNF to manage kernel packages.

This allows you to have a container file that is as simple as:

```dockerfile
FROM quay.io/fedora/fedora-bootc:42
RUN <<EOF
set -xeuo pipefail
dnf -y downgrade kernel
dnf clean all
bootc container lint
EOF
```

An example for kernel-rt on CentOS is:

### Containerfile

```dockerfile
FROM quay.io/centos-bootc/centos-bootc:stream10
RUN <<EOF
set -xeuo pipefail
dnf config-manager --set-enabled rt
dnf config-manager --set-enabled nfv
(echo 'remove kernel kernel-modules-core'; echo 'install kernel-rt-modules-extra kernel-rt-modules-kvm'; echo run) | dnf -y shell
dnf clean all
bootc container lint
EOF
```

If you are on an older image, you can use `rpm-ostree override replace` or
`rpm-ostree override remove pkg --install new-pkg` to manage your kernel.
An example of using rpm-ostree is available at our [examples
repository](https://gitlab.com/fedora/bootc/examples).

## GitHub Actions

You may want to build a derived bootc image on a GitHub project via
GitHub Actions. Since bootc-based images can grow in size quickly, you
are likely to run into disk-space issues on the Action runner. Adding
the following first step to the Action may solve the space issue:

```yaml
    # Based on https://github.com/orgs/community/discussions/25678
    - name: Delete huge unnecessary tools folder
      run: rm -rf /opt/hostedtoolcache
```

For an example project on GitHub using the Buildah and Podman Actions,
please visit [nzwulfin/cicd-bootc](https://github.com/nzwulfin/cicd-bootc).

## Container metadata

While one can add [Container configuration
metadata](https://github.com/opencontainers/image-spec/blob/main/config.md)
(e.g., environment, exposed ports, default users) to an OCI container
image, bootc generally ignores that. In practice, that means that
certain things may work when being run as an ordinary OCI container via
Podman but won't work once booted. For instance, you may use the `ENV
foo=bar` instruction in a Containerfile which will be visible in a
Podman container but it won't be propagated to the booted system.

For details and recommendations, please refer to the
[bootc-runtime documentation](https://bootc-dev.github.io/bootc/building/bootc-runtime.html).

## Performing "targeted" updates

One scenario that may occur is when one wants to perform e.g. **just** a
kernel patch to a running system; or other targeted fixes, without
rolling in other changes. One recommendation for this type of scenario
is (assuming you have orchestration/management software) to have an
inventory of which container image (identified by `@sha256`) is in use
for each machine you want to target for specific updates. Then create a
container build which has just the changes you want, and have the
targeted nodes use that container image via e.g. `bootc switch`.

## Lifecycle binding code and configuration

At the current time, the role of `bootc` is solely to boot and upgrade
from a single container image. This is a very simplistic model, but it
is one that captures many use cases.

In particular, the default assumption is that **code** and
**configuration** for the base OS are tightly bound. Systems which
update one or the other asynchronously often lead to problems with skew.

## Containerized vs 1:1 host:app

A webserver is the classic case of something that can be run as a
container on a generic host alongside other workloads. However, many
systems today still follow a "1:1" model between application and a
virtual machine. Migrating to a container build for this can be an
important stepping stone into eventually lifting the workload into an
application container itself.

Additionally in practice, even some containerized workloads have such
strong bindings/requirements for the host system that they effectively
require a 1:1 binding. Production databases often fall into this class.

## httpd (bound)

Nevertheless, here's a classic static http webserver example; an
illustrative aspect is that we move content from `/var` into `/usr`. It
expects an `index.html` colocated with the Containerfile.

### Containerfile

```dockerfile
FROM quay.io/fedora/fedora-bootc:42
# The default package drops content in /var/www, and on bootc systems
# we have /var as a machine-local mount by default. Because this content
# should be read-only (at runtime) and versioned with the container image,
# we move it to /usr/share/www instead.
RUN dnf -y install httpd && \
    systemctl enable httpd && \
    mv /var/www /usr/share/www && \
    echo 'd /var/log/httpd 0700 - - -' > /usr/lib/tmpfiles.d/httpd-log.conf && \
    sed -ie 's,/var/www,/usr/share/www,' /etc/httpd/conf/httpd.conf
# Further, we also disable the default index.html which includes the operating
# system information (bad idea from a fingerprinting perspective), and crucially
# we inject our own content as part of the container image build.
# This is a key point: In this model, the webserver content is lifecycled exactly
# with the container image build, and you can change it "day 2" by updating
# the image. The content is underneath the /usr readonly bind mount - it
# should not be mutated per machine.
RUN rm /usr/share/httpd/noindex -rf
COPY index.html /usr/share/www/html
EXPOSE 80
```

## httpd (containerized)

In contrast, this example demonstrates a webserver as a "referenced"
container image via
[podman-systemd](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
that is also configured for automatic updates.

This reference example is maintained in the
[app-podman-systemd](https://gitlab.com/fedora/bootc/examples/-/tree/main/app-podman-systemd)
examples directory.

### caddy.container

```text
[Unit]
Description=Run a demo webserver

[Container]
# This image happens to be multiarch and somewhat maintained
Image=docker.io/library/caddy
PublishPort=80:80
AutoUpdate=registry

[Install]
WantedBy=default.target
```

#### Containerfile

```dockerfile
# In this example, a simple "podman-systemd" unit which runs
# an application container via podman-systemd.unit(5)
# (https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
# that is also configured for automatic updates via podman-auto-update(1)
# (https://docs.podman.io/en/latest/markdown/podman-auto-update.1.html)
FROM quay.io/centos-bootc/centos-bootc:stream9
COPY caddy.container /usr/share/containers/systemd
# Enable the simple "automatic update containers" timer, in the same way
# that there is a simplistic bootc upgrade timer. However, you can
# obviously also customize this as you like; for example, using
# other tooling like Watchtower or explicit out-of-band control over container
# updates via e.g. Ansible or other custom logic.
RUN systemctl enable podman-auto-update.timer
```

## Authentication, users and groups

The container images above are just illustrative demonstrations that are
not useful standalone. It is highly likely that you will want to run
other container images, and perform other customizations.

Among the most likely additions is configuring a mechanism for remote
SSH; see [Authentication, Users, and Groups](https://docs.fedoraproject.org/en-US/bootc/authentication/).

## Invoking `useradd` as part of a container build

Often packaging scripts may invoke `useradd`. This can cause "state
drift" in the case where `/etc/passwd` is also locally modified on the
system, and transient `/etc` is not in use.

More on this in the [bootc upstream users-and-groups documentation](https://bootc-dev.github.io/bootc/building/users-and-groups.html#adding-users-and-credentials-statically-in-the-container-build).

If the user does not **own** any content shipped in `/usr` and it runs
as a systemd unit, then it's often a good candidate to convert to
systemd `DynamicUser=yes`, which has numerous advantages in general.
Using `DynamicUser` will also help take care of ownership of e.g.
`/var/lib/somedaemon` (`StateDirectory` and more).

However, porting to `DynamicUser=yes` can be somewhat involved in
complex cases. If the RPM does contain files owned by the allocated
user, but that content is just in e.g. `/var/lib/somedaemon` or
`/var/log/somedaemon`, then often the best fix is to drop that content
from the RPM (you can `%ghost` it to mark it as owned) and switch to
creating it at runtime via
[systemd-tmpfiles](https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html).

You can then also switch to creating the user via
[systemd-sysusers](https://www.freedesktop.org/software/systemd/man/latest/systemd-sysusers.html).

And at that point, you can also drop the `%post` from the RPM which
allocates the user.

### When your package owns content shipped in `/usr`

This occurs in the case of things like setuid/setgid binaries. The first
solution: Avoid setuid/setgid binaries entirely! Usually, there's a
better approach to the problem domain.

Another case is where a daemon wants to drop privileges but wants to
access its configuration state in `/etc`. For example, polkit does this
in `/etc/polkit-1/rules.d`. One solution here is to use e.g.
`BindReadOnlyPaths=` to mount the source directory into the namespace of
the daemon.

If you are in this situation, then there is no solution other than
statically allocating the user, which requires global coordination. You
can request it e.g. via
[Fedora](https://docs.fedoraproject.org/en-US/packaging-guidelines/UsersAndGroups/#_soft_static_allocation).
But this should be avoided to the greatest extent possible.

## General configuration guidance

See the [bootc upstream guidance](https://bootc-dev.github.io/bootc/building/guidance.html).

Many configuration changes to a Linux system boil down effectively to
writing configuration files into `/etc` or `/usr` - those operations
translate seamlessly into booted hosts via a `COPY` instruction or
similar in a container build.

## Referencing configuration as a container artifact

Custom bootc image uses the 'artifact pattern' to reference other
container images as reusable components. This approach enables you to
manage and reuse software pieces independently across multiple container
images, rather than duplicating configuration in each image.

Copy any configuration from referenced images before applying additional
customizations. This step should be performed early in the build process
to ensure consistency and avoid conflicts.

```dockerfile
FROM quay.io/centos-bootc/centos-bootc:stream10 as builder
RUN /usr/libexec/bootc-base-imagectl build-rootfs --manifest=standard /target-rootfs

# This container image uses the "artifact pattern"; it has some
# basic configuration we expect to apply to multiple container images.
# Define baseconfig for the image, leveraging the "artifact pattern" to reference a reusable container artifact.
FROM quay.io/exampleos/baseconfig@sha256:.... as baseconfig

FROM scratch
COPY --from=builder /target-rootfs/ /

# Copy configuration artifacts from the baseconfig container image to our custom image.
COPY --from=baseconfig /usr/ /usr/

# ... insert here arbitrary build steps, as above
LABEL containers.bootc 1
LABEL ostree.bootable 1
RUN bootc container lint
```

## More examples

See the [Fedora bootc examples repository](https://gitlab.com/fedora/bootc/examples) for many examples of container image definitions!
