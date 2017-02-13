---
layout: post
title:  "WebApps with Traefik LoadBalancing"
date:   2017-02-03 10:51:47 +0530
author: "Sébastien Allamand (allamand)"
categories: webapps
tags: [docker, webapp]
img: traefik.png
terms: 2
---

### Before anything How to use this course

Please, validate the Google capcha to activate the shell on the right.
Then, you can either copy by yourself commands, or you can click on grey boxes to automatically copy commands

```.term1
echo 'execute command on node1!!'
```
```.term2
echo 'execute command on node2!!'
```

>Please note that this platform is not secure and you should not store personal datas<br>
>the instance will be removed after few hours


## Predictive Load-balancing name using Traefik

We will leverage the power of Docker Swarm Mode of docker 1.13, with great features of Traefik Proxy in this course.



In this advance scenario we need to set-up a LoadBalancer Named **Traefik**, which will uses Docker **Events** informations to dynamically set-up LoadBalancing Rules according do Docker Labels define at Containers Launch (start/stop..)

It is using docker **service labels** to define the metadata and rules for dynamically configure routing rules from traefik to real applications (on whichever Host they are within a Docker Swarm Cluster).

### First we will enable the Swarm mode

> in this tuto wi will only uses a 2 nodes swarm cluster, but it will works exactly the same with more nodes!

```.term1
docker swarm init --advertise-addr=$(hostname -i)
```

> Copy the join command output and paste it in the other terminal, to form a 2 node swarm cluster


## show members of swarm

```.term1
docker node ls
```

If you correctly execute, the above command, you must see 2 nodes :
```

$ docker node ls
ID                           HOSTNAME  STATUS  AVAILABILITY  MANAGER STATUS
7p167ggf1wi3ox52z8ga2myu6 *  node1     Ready   Active        Leader
og1irjjh2fjtwt7dko7ht0qnq    node2     Ready   Active
```

### Create Traefik LoadBalancer Docker Container

We start creating the Docker Compose file traefik.yml :

>You can Click on the grey box to automatically copy the content on the terminal (don't mess with the order of commands ;) )


```.term1
cat <<EOF > traefik.yml
version: "3"

services:
  traefik:
    image: traefik
    command: --web --docker --docker.swarmmode --docker.watch --docker.domain=traefik --logLevel=DEBUG
    ports:
      - "80:80"
      - "8080:8080"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /dev/null:/traefik.toml

    labels:
      - "traefik.enable=false"
    networks:
      - public
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]		                                                   
      restart_policy:
        condition: on-failure
      
networks:
  public:
    driver: overlay
    ipam:
      driver: default
      config:
      - subnet: 10.1.0.0/24

EOF
```

- we use version 3 of compose file (mandatory for docker stack deploy)
- we uses image traefik from docker Hub
- docker will create an overlay networks named public, on which will will plug every container we want to publish
- we uses a constrains to deploy the service on a swarm manager


### Launch the LoadBalancer Docker Container

```.term1
docker stack deploy traefik --compose-file traefik.yml
```

The Load Balancer is configured to listen on port 80,443 HTTP traefik, and also provide a web dashboard that is exposed on port 8080.

The use of docker socket allows traefik to listen to the Docker Host Daemon events, and reconfigure itself when containers are started/stopped. 
>To work with a swarm cluster with TLS security layer, the configuration to launch the Traefik container will be different.

Check docker networks

```.term1
docker network ls
```

You can see that a specific network **traefik_public** has been created.

Later If we want others containers to be able to be published through the traefik load balancer we will need to **attached them** also to this network.

>One container can be attached to severals differents networks

### See Your Docker Swarm Stack

List all your deployed stacks, and view detailed on a specific stack

```.term1
docker stack ls
docker stack ps traefik
```

View logs of our Traefik service

```.term1
docker service logs --tail=10 traefik_traefik
```


### See LoadBalancer Dashboard

Traefik also have a Web UI which has been deployed on port 8080 on url which will be something like :

```
http://ip10_0_3_3-8080.pwd.allamand.com/
```

> Change the ip part (**10_0_3_3**) with the ip of your node with "_" instead of ".". (look at your shell prompt)<br>
> Please correct the url and try to open in the browser

For know the dashboard must be empty



### Deploy our first service and plug it with Traefik Load Balancer


**Traefik** load balancer is listening to **docker swarm events** informations, and will auto-reconfigured based on the service's metadatas, we need to configure thoses metadata as docker service labels:

#### Configure service with routing based on URL Path

We can set a label telling traefik to route the traffic according to the target service URI Path using `traefik.frontend.rule` label:

```.term1
cat <<EOF > http.yml
version: "3"

services:
  http:
    image: emilevauge/whoami
    networks:
      - traefik_public
    deploy:
      replicas: 1
      labels:
        - "traefik.backend=http"
        - "traefik.port=80"
        - "traefik.frontend.rule=PathPrefixStrip:/http/"
        - "traefik.docker.network=traefik_public"

networks:
  traefik_public:
    external: true

EOF
```

> !!Note: Because we are working with Docker Swarm Mode, labels must be set at the **service** level in the **deploy** section, instead of at **container** level when using classique swarm!!

#### launch the container


```.term1
docker stack deploy http --compose-file http.yml
```

We have attached the http container on the network **traefik_public**. we have now 2 containers connected to that network we can inspect with :

```.term1
docker network inspect traefik_public
```

Check again the Traefik Dashboard
```
http://ip10_0_3_3-8080.pwd.allamand.com/
```
>don't forget to adapt the url to your context



We can also call the **Traefik API** to retrieve informations from the Load Balancer

```.term1
curl http://localhost:8080/api/providers
```


#### request the service

>we have defined that our service will be requested if it starded with the path **/http/**, using the traefik **PathPrefixStrip** rule in label **traefik.frontend.rule**


```.term1
curl http://localhost/http/
```

we can see in response that it is the http container that make the response

You can Request the service directly expose on :
```
http://ip10_0_3_3-80.pwd.allamand.com/http/
```
>don't forget to adapt the url to your context

You can request the logs of the Traefik Load Balancer:

```.term1
docker service logs --tail=10 traefik_traefik
```

You can request the logs of the application
```.term1
docker service logs --tail=10 http_http
```



### Scaling Service

We can use docker-compose to scale some services of our applications: Exemple, scale 5 instances of the http service:

```.term1
docker service scale http_http=5
```

Check that you have 5 instances of the service :

```.term1
docker service ps http_http
```

You can make local calls to the http service and see the loadbalancing :

```.term1
curl http://localhost/http/
```

On every request, it's a different docker container that will respond!

You can also see that http service has several backend configured in the **Traefik Dashboard**


### Understanding the docker network mechanism

we now have 5 instances of our services http which are deployed on both node1 and node2.
- On each node, there are some instances.
- On each node, there are a network called **traefik_public**
- if we inspect the content of traefik_public on each node, we will only see containers that belong to that node


On node1:
```.term1
docker network inspect traefik_public | grep http
```

On node2:
```.term2
docker network inspect traefik_public | grep http
```

> Note also that in the Traefik Dashboard, you'll find only 1 IP.<br>
> This is the IP ov the internal VIP for the http service<br>
> Which load balance on different instances of http service!

Use the following command to find out what it the VIP IP of our service :

```.term1
curl http://localhost:8080/api/providers | jq '.docker.backends."backend-http".servers."server-http_http"'
```



## Deploy a Microservice Application

We Have see how we can leverage Docker labels to dynamically customize our LoadBalancing routing rules, and docker-compose to create and links services together.

Now let's try to launch a **more complicated** Microservice application.

We will uses the **docker's vote** microservice application with custom labels to be used within our traefik loadbalancer.

<img src="https://github.com/allamand/example-voting-app/raw/master/traefik_voting.png" width="600">

Which is composed of :
- A Python webapp which lets you vote between two options
- A Redis queue which collects new votes
- A Java worker which consumes votes and stores them in…
- A Postgres database backed by a Docker volume
- A Node.js webapp which shows the results of the voting in real time
 					

### Run voting microservice application

First you need to Retrieve voting-app application 

```.term1
git clone https://github.com/allamand/example-voting-app.git
```

Go to the stack directory 

```.term1
cd example-voting-app
```

and launch the app using docker-compose file, you can view the **docker-compose-pwd.yml** file

```.term1
docker stack deploy cloud -c docker-compose-pwd.yml
```

> This command will build each part of the microservice from sources.
> It may take a little time to get all services up & running (time to download images..)
> You can take a coffee since this may take a little to finish ;)


you can monitore the setup state using


```.term1
docker stack ps cloud
```

> Be carreful, the Output shows two state columns :
> - **Desired State** which represents what you are asking to swarm
> - **Current State** which is the current state of the container (which may be stuck in Preparing for a moment while downloading the images).

Once All container are in **Running** state, you can start test the application


Check the **Traefik Dashboard** and will see that two new entries was added (*frontend-PathPrefixStrip-result* & *frontend-PathPrefixStrip-vote*)


#### You can now make your Vote!!
```
http://ip10_0_2_3-80.pwd.allamand.com/vote/
```
>don't forget to adapt the url to your context

or locally :
```.term1
curl http://localhost/vote/
```


#### And See the results of votes
```
http://ip10_0_2_3-80.pwd.allamand.com/result/
```
>don't forget to adapt the url to your context

```.term1
curl http://localhost/result/
```


you can see the logs of the services :
```.term1
docker service logs --tail=10 cloud_vote
```


> In future version we would be able to watchs all logs running
> **docker stack logs cloud** but it's still expérimental the time of writing



You are now able to deploy any stack on Docker Swarm Mode using docker-compose and Traefik Proxy!


Note:

> Using Traefik, it is generally recommended to uses the Host-based instead of the Path-based Proxification we used in this tutorial.<br>
> We used this because with Play-With-Docker, there already a Host-based routing to target your instances of service (i.e: traefik).

To use Host-based Proxification with trafik, just uses a label like :

```
    labels:
      - "traefik.backend=test2"
      - "traefik.port=80"
      - "traefik.frontend.rule=Host:myservice.myhost.com"
```


>Traefik is not yet able to Proxify TCP request, you can look at docker-flow-proxy from vfarcic for that purpose.