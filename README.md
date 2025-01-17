What is this?
=============

This repository is just a fork with minor modifications of [the official Docker build of ejabberd](https://github.com/processone/docker-ejabberd).

You will find more instructions there.

Check out the [Readme](https://hub.docker.com/r/ballerburg9005/docker-ejabberd-ecs-official-arm ) I wrote on Dockerhub for more important information.

How to build the official Docker images
=======================================

1. docker buildx build --platform linux/arm64,linux/armhf,linux/amd64 --push -t ballerburg9005/docker-ejabberd-mix-official-arm mix
2. docker buildx build --platform linux/arm64,linux/armhf,linux/amd64 --build-arg VERSION=${1:-$(date +%y%m -d '1 month ago')} --build-arg VCS_REF=\`git rev-parse --short HEAD\` --build-arg BUILD_DATE=\`date -u +"%Y-%m-%dT%H:%M:%SZ"'\` --push -t ballerburg9005/docker-ejabberd-ecs-official-arm ecs #this is the command from ecs/build.sh


If buildx is not working for you, try this quick tutorial to set it up:

https://ballerburg.us.to/index.php/howto-multi-architecture-builds-in-docker/


<details>
  <summary>Click if you don't want to use this fork but the official repo</summary>
  
.
  
In order to build ejabberd with ARM included, you simply have to adapt some three corresponding lines in build.sh and the Dockerfile inside the ecs folder:

1. FROM ballerburg9005/docker-ejabberd-mix-official-arm as builder
2. current=$(date +%y.07) # I had to use the previous month "07" in the version string, because there was not a git branch yet for this month
3. docker buildx build --platform linux/arm64,linux/armhf 

First build the mix image using buildx like suggested in #3, and then the ecs image via ./build.sh with your mix image referenced as demonstrated in #1.
	
If you want the captcha, you have to add the packages suggested in the Readme to the list of packages in the ecs image at the end (not mix!).

Also you can add those extra modules. Add this right before setup runtime environment:

```
# docker buildx "containers" have no network isolation (even with --isolation=true)
# so we need to check if the ports are blocked by another instance and sleep until they are open again

RUN bash -c 'while(true); do if netstat -putlan | grep 5222; then sleep $((1 + $RANDOM % 60)); else break; fi; done \
		&& bin/ejabberdctl start \
		&& sleep 30 \
		&& bin/ejabberdctl modules_update_specs \
		&& bin/ejabberdctl module_install mod_default_rooms \
		&& bin/ejabberdctl module_install mod_default_contacts \
		&& bin/ejabberdctl stop \
		&& killall epmd'
```

Lastly, there is a minor bug in the registration captcha-ng.sh file. You have to change two lines. See this PR I made: https://github.com/processone/ejabberd/pull/3660 . Even if you don't fix it, it will still work most of the time.

</details>
