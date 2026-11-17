# docker-ejabberd — multi-architecture fork

Fork of [processone/docker-ejabberd](https://github.com/processone/docker-ejabberd),
synchronized with upstream October 2026 Docker packaging, with the ejabberd
**26.09** release as the default build target.

## Compatibility

The published Docker Hub names are unchanged:

- `ballerburg9005/docker-ejabberd-mix-official-arm`
- `ballerburg9005/docker-ejabberd-ecs-official-arm`

The image continues to run as UID/GID **9000:9000** with
`/home/ejabberd/{conf,database,logs,upload}` volumes,
`/home/ejabberd/bin/ejabberdctl` entrypoint, and the existing XMPP ports.
The two contributed registration modules (`mod_default_rooms` and
`mod_default_contacts`) remain preinstalled. CAPTCHA supports both the
upstream `/home/ejabberd/bin/captcha-ng.sh` location and the old
`lib/ejabberd-*/priv/bin/captcha-ng.sh` location.

**Back up your persisted configuration and database before upgrading an
existing 2021-era ejabberd deployment.** This preserves the image's external
interface, not ejabberd's old database schema or deprecated config syntax.
See the [official upgrade documentation](https://docs.ejabberd.im/admin/upgrade/).

## Build and publish (Buildx required)

Login to Docker Hub and select an appropriate multi-platform builder, with
QEMU/binfmt emulation or native ARM worker nodes. Then from the repository root:

```sh
docker login
./build-multiarch.sh 26.09
```

The old entry point also works:

```sh
cd ecs
./build.sh 26.09
```

Both commands publish the MIX builder image **first**, then the ECS runtime
image. Each image is built with **all selected architectures in one parallel
Buildx invocation**, matching the original multi-platform workflow. The
script **never** builds or publishes individual architectures one-by-one,
including on upload failure. Instead, it retries the same multi-platform
Buildx command (up to three attempts by default) and then exits on failure.
No per-architecture tags or manifest assembly commands are used.

Both images are tagged `:26.09` and `:latest` and retain the original
Docker Hub repository names. **BuildKit caches are not necessarily shared
between the default Docker builder and a named docker-container builder, or
between different users.** Use the same Buildx builder consistently.

For subsequent ECS-only rebuilds when the MIX `:26.09` manifest **has
already been fully published**, omit rebuilding MIX:

```sh
SKIP_MIX=1 ./build-multiarch.sh 26.09
```

Changing `BUILD_DATE` or `VCS_REF` changes only ECS image metadata and
does not invalidate dependency compilation. Configure retry count using
`PUSH_ATTEMPTS=5` or the delay with `PUSH_RETRY_DELAY=30`. The
`--provenance=false --sbom=false` flags reduce extra registry uploads.

The default target platforms are:

```
linux/amd64,linux/arm64,linux/arm/v6,linux/arm/v7
```

ARM v6 is the Alpine `armhf` architecture originally requested; ARM v7 is
included as well. To restrict architectures or use a testing registry:

```sh
PLATFORMS=linux/amd64,linux/arm64 \
MIX_IMAGE=yourname/test-ejabberd-mix \
ECS_IMAGE=yourname/test-ejabberd-ecs \
./build-multiarch.sh 26.09
```

**Important:** This command uses `--push`. It publishes to the named
registry; it does not merely create a local single-platform Docker image.
Do not run it without checking the image names.

## Why the old hacks disappeared

- [CAPTCHA fix PR #3660](https://github.com/processone/ejabberd/pull/3660)
  merged upstream in August 2021. The release's `captcha-ng.sh` is the same
  as this fork's old patched script. The fork copy and checksum substitution
  are no longer necessary.
- `imagemagick`, `ghostscript-fonts`, and `bash` are still installed for
  the sample CAPTCHA generators.
- The randomized `netstat`/sleep workaround and netcat reverse consoles are
  removed. `module_install` still needs a running ejabberd node, so the image
  temporarily starts one **with no XMPP or HTTP listening ports**, and with
  EPMD disabled via `ERL_DIST_PORT` (random per build). This does not rely on
  Docker's `--isolation` flag. Check simultaneous builds on your Buildx driver.
- The 2021 Alpine 3.11 + Distillery build is replaced by Alpine 3.23
  + `mix release`. The old hard-coded `21.07` version fallback is removed.
- Alpine 3.24 is avoided for now: its Erlang/OTP 27 build crashes
  with `Failed to set alternate signal stack` on some newer x86_64 CPUs.
  Alpine 3.23 uses the older musl base; recheck when the release uses fixed OTP.
- Upstream's Go-based `ejabberdapi`, `tini` entrypoint, and refreshed example
  configuration are used. The old binary bundled in this repository is removed.
- `ecs/build.sh` still works, but now first publishes the required compatible
  multi-architecture MIX image. This avoids referencing an old builder image.

### Verify the published image

```sh
docker buildx imagetools inspect ballerburg9005/docker-ejabberd-ecs-official-arm:26.09
docker run --rm --platform linux/amd64 --entrypoint sh \
  ballerburg9005/docker-ejabberd-ecs-official-arm:26.09 \
  -c 'test -x bin/captcha-ng.sh && test -d .ejabberd-modules/mod_default_rooms && test -d .ejabberd-modules/mod_default_contacts'
```

## Status

The repository migration was prepared by comparing against upstream and
checking the latest source. A real Docker build, full ARM/QEMU validation,
CAPTCHA rendering test, concurrent-build test, and a deployment migration test
are necessary before replacing a production container. GitHub Actions runs
an amd64 smoke test; a manual full multi-architecture build is still required.

For upstream documentation see [processone/docker-ejabberd](https://github.com/processone/docker-ejabberd).
