---
layout: post
title:  "Cassandra Monitoring with Prometheus"
date:   2017-03-07 10:00:00 +0000
author: "Sébastien Allamand (allamand)"
categories: cassandra
tags: [docker, cassandra]
img: cassandra_prometheus_logo.png
terms: 2
---



## Cassandra Cluster Monitoring

In the previous Post we have seen how to setup a Cassandra cluster within a Docker Swarm Mode Cluster.

In this post we will redeploy same cluster as in previous, but we will add prometheus monitoring.
If you have not followed previous post you may want to go there first.

## Create Swarm cluster

> in this tuto wi will only uses a 2 nodes swarm cluster, but it will works exactly the same with more nodes!

```.term1
docker swarm init --advertise-addr=$(hostname -i)
docker swarm join-token manager
```
> Copy the join command to add master output and paste it in the other terminal, to form a 2 node swarm cluster

```.term1
docker node ls
```
should show 2 master nodes


Now we retrieve our applications files

```.term1
git clone https://github.com/allamand/cassandra-docker.git
```

## Create Cassandra Cluster

We will use a github repo where I have setup same configuration as in previous post on : https://github.com/allamand/cassandra-docker

### Deploy a local docker registry

Before building our images, we will deploy a docker registry so that our images can spread in the cluster

```.term1
docker stack deploy registry -c ~/cassandra-docker/stacks/registry.yml
export REGISTRY_SLASH=127.0.0.1:5000/
```

```.term1
docker service ps registry_registry
```

>This may take little time for the image to be downloaded and the container to be startef

you can check with 

```.term1
curl 127.0.0.1:5000/v2/_catalog
```

### Build docker images

- Build custom cassandra image with jmx node exporter
```.term1
docker-compose -f ~/cassandra-docker/stacks/cassandra-node.yml build
docker-compose -f ~/cassandra-docker/stacks/cassandra-node.yml push
```
- Build custom prometheus image with configuration to reach cadvisor, node-exporter and cassandra-jmx
```.term1
docker-compose -f ~/cassandra-docker/stacks/prometheus.yml build
docker-compose -f ~/cassandra-docker/stacks/prometheus.yml push
```

Now we may have 2 images in our registry

```.term1
curl 127.0.0.1:5000/v2/_catalog
```

should print something like
```
{"repositories":["cassandra","prometheus"]}
```

### Launch the Cassandra Seed

```.term1
docker network create --attachable --driver overlay cassandra_net
docker stack deploy cassandra-seed --compose-file ~/cassandra-docker/stacks/cassandra-seed.yml
```

Wait few minutes for the cassandra seed to boot properly

```.term1
docker stack ps cassandra-seed 
```

Check the log

```.term1
docker service logs cassandra-seed_cassandra-seed
```

### Launch the Cassandra Node Stack

```.term1
docker stack deploy cassandra-node --compose-file ~/cassandra-docker/stacks/cassandra-node.yml
```

let's watch the progression of cassandra-node services in the second terminal :
Wait for the node to be "running", it may be in "preparing" while downloading image from docker hub.

```.term2
watch docker stack ps cassandra-node
```

>Please note that the new cassandra will wait 30s to receive datas from the cassandra-seed
>Since if have put replicas:3, swarm will try to start 3 cassandra-node replicas. Since only one node can register on cassandra at a time, the 2 others will fail several times until all previous nodes are already registered.
>This can take several minutes to achieve

Check the log

```.term1
docker service logs cassandra-node_cassandra-node 
```


## Testing the service

```.term1
docker exec $(docker ps -q --filter name=cassandra-node) nodetool status
```

We can see that our cluster have 4 nodes “UN” (Up & Normal). Our cluster is ready !

> If you have the error message no such container, you can try to copy this request on the other terminal

### Running the CQL Shell in a Container

Our cluster is running, so let's create a table and insert data using the CQL Shell which comes within Cassandra
We create a new Cassandra container for the sole purpose of executing our CQL Shell. We must plug this container on our `cassandra_net` overlay network.


```.term1
docker run --rm -ti --network cassandra_net ${REGISTRY_SLASH}cassandra cqlsh -u cassandra -p cassandra tasks.cassandra-node
```

Once in the CQLShell you can type this examples commands:

```.term1
CREATE KEYSPACE Test WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 3 };
CREATE TABLE Test.users (firstname varchar, lastname varchar, info varchar, creation timeuuid, PRIMARY KEY((firstname), creation));
INSERT INTO Test.users (firstname,lastname,info,creation) VALUES ('jean','valjean','el warior', now());
INSERT INTO Test.users (firstname,lastname,info,creation) VALUES ('paul','palovsky','personnel', now());
SELECT * from Test.users;
```


```.term1
SELECT firstname, dateOf(creation), info FROM Test.users WHERE firstname='jean' ORDER BY creation;
``` 

> type `exit` to Exit the cqlsh client tool

## Monitoring Cassandra with Prometheus

Cassandra is one of many Java-based systems that offers metrics via JMX. The [JMX Exporter](https://github.com/prometheus/jmx_exporter) offers way to use these with [Prometheus](https://prometheus.io/)


We already add the JMX exporter java agent in our cassandra docker image `seb/cassandra` so that cassandra expose it's JVM metricks through JVM exporter on port 31500.


We can request directly thoses metrics :
```.term1
docker run --rm -ti --network cassandra_net sebmoule/ubuntu:16.04 curl http://tasks.cassandra-node:31500/metrics
```

..But better way will be using prometheus and grafana for this monitoring


## Deploy Prometheus & Grafana stack

Prometheus will collect cassandra metrics from each cassandra-node on `cassandra_net` overlay network, and grafana will enable to graph thoses data.

```.term1
export PASSWORD=secretpassword
docker stack deploy prometheus -c ~/cassandra-docker/stacks/prometheus.yml
```

let's check the stack deploy properly

```.term1
docker stack ps prometheus
```

No you can access the Prometheus on the port 9090 and Grafana on the port 3000

```
http://pwd10_0_3_3-9090.pwd.allamand.com/targets
http://pwd10_0_3_3-3000.pwd.allamand.com/
```

> Change the ip part (**10_0_3_3**) with the ip of your node with "_" instead of ".". (look at your shell prompt)<br>
> Please correct the url and try to open in the browser

- the targets request on prometheus must list all of metrics provider endpoints enabled.
- The login / password for grafana is admin / $PASSWORD


### Configuring Grafana

We need to configure grafana with proper informations.
- Click on `Add data source`
  - in **Type** select `prometheus` with name `prometheus`
  - cick `Add`
  - In **Http settings** set the url to `http://prometheus:9090` with Access type `proxy`
  - Click **Save & Test** and light should be green ;)

![](../images/prometheus_source.png)

- Go to Dashboard and create **New Dashboard**
  - Click on Import and past the cassandra dashboard url to download : https://grafana.net/dashboards/371
  - Click and **Load**
  - Then select Prometheus data soruce and click on **Import**

![](../images/prometheus_import.png)

Now you should have a Monitoring dashboard looking like

![](../images/cassandra_prometheus.png)

with cassandra metrics

![](../images/cassandra_metrics.png)


## Free unused ressources

```.term1
docker stack rm prometheus
docker stack rm cassandra-node
docker stack rm cassandra-seed
docker stack rm registry
```