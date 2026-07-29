Grab it from https://hub.docker.com/r/akiessling/php-deployment/tags

## Build and publish

Run the interactive helper:

```bash
./build-and-push.sh
```

It detects the current Composer version, updates the `Dockerfile`, builds the
`linux/amd64` image, derives the installed PHP version and creates both the
versioned tag (for example `8.4-2.10.2`) and `latest`. It asks for confirmation
before pushing either tag to Docker Hub. After a successful build, it also
commits the `Dockerfile` with a message such as
`rebuild image with composer 2.10.2` and creates the matching Git tag
`8.4-2.10.2`. The Git commit and tag remain local until pushed separately.

To use a specific Composer version without automatic detection:

```bash
./build-and-push.sh 2.10.2
```

`IMAGE` and `PLATFORM` can be overridden when needed:

```bash
IMAGE=example/php-deployment PLATFORM=linux/arm64 ./build-and-push.sh
```
