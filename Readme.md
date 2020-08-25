# Francisco Fregona's submission for the Site Reliability Engineer position at Balanced Patena.io.

Prerequisites
=============

To run this code challenge you'll need a couple of things:

* Access to a Kubernetes cluster. Or vagrant and 8GB of ram to host the whole cluster.
* Ansible to deploy the images.
* Git, naturally.

Vagrant tested version: 2.2.2
Ansible tested version: 2.8.6

How to use this
===============

Take a look at the vagrant/Vagrantfile file and set IP's appropriate to your network (lines 10, 19 and 28... I'm sorry but it's 1AM on a Tuesday).
Put an entry on your /etc/hosts file pointing to the cluster master IP address:
``192.168.100.110	secretid api.secretid web.secretid prometheus.secretid``

Then modify the files at ansible/inventory/vagrant/host_vars with the correct IPs.

And, finally, create the cluster with:
```bash
cd vagrant
vagrant up
```
And configure it with:
```bash
cd ..
ansible-playbook deploy.yml
```

If this fails to run, please feel free to contact me and I'll sort it out. I can see it's far from perfect, but I chose to focus on the harder parts (k8s specially)

#### Service URLS:

* Web: web.secretid:80/ and web.secretid:443/
* Api: api.secretid:80/randomName and api.secretid:443/randomName


The web service and Kubernetes
=============================

I couldn't find an easy enough example of a web service hitting an API and a postgres database so I made my own.

I created a database out of the 500 most popular baby names for boys and 500 for girls. Those were dumped into a table "firstnames". Then I did the same with the 1000 most popular last names and those went to the "lastnames table". The API service generates 2 random numbers as indexes to this tables and composes a random name. And the web service consumes this API service and builds a pretty web page for it for secret agents in need of a new identity.

I have a sense that this challenge could have been solved within the capabilities of Docker + Swarm. But I wanted a project to actually do something with rubbernecks, and expose myself to the challenge and learn all those things never get into the tutorials.


## Zero downtime updates

Again, from the [rubbernecks official docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment):

To update an application running on a deployment (lets say, the web deployment), we would simply issue:
kubectl set image deployment/web web=web:newversion --record

And Kubernetes would take care of rolling out the old and in the new versions.

The rollout command offers the history and the undo modes to check on the history of the deployment and fixing mistakes, but it is advised care with this strategy, as it will not leave a trace in the configuration files (ie: it is not committed to code). It can save valuable time in production but it has to be fixed in the code before it is forgotten to.

Additionally, when rolling out a deployment, the values maxUnavailable and maxSurge specify how many (or what percentage) of pods are to become unavailable, and how many of them are to be created at the same time; thus, allowing us to control the speed and impact of the updates.

MaxUnavailable = 100% would be the same as recreating the deployment. MaxUnavailable set to 50% would mean that half of the service would immediately be called to terminate. The MaxSurge parameter, on the other hand, controls how much extra infrastructure we will have to allocate to host new pods. A maxSurge of 100% equates to a Blue/Green deployment, where the controller spins up the new version and switches off the old one once it is deemed healthy.

## Scaling the components

```
kubectl scale deployments/API --replicas=2
```

``deployment.apps/API scaled
vagrant@k8s-head:\~/k8s/k8syamls$ kubectl get pods
NAME                                     READY   STATUS        RESTARTS   AGE
API-67b767c5d-l7wtj                      1/1     Terminating   0          3m51s
API-67b767c5d-n66jw                      1/1     Running       0          3m51s
API-67b767c5d-wlb8w                      1/1     Running       0          3m51s``

And pretty much the same can be done with the web ~~service~~ deployment.

For the database, the thing is a tad more complicated.

First I'd allocate storage space in another server/node and set a slave postgres database. Pods would have to be instructed for anti-affinity (no use on having both master and slave in the same node) and switch over Master->Slave would have to be configured and tested thoroughly. More on that later.

Kubernetes also includes the possibility of auto scaling the services, as per [this](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/) article with just a single *kubectl autoscale* command.

And further reading: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#scaling-a-deployment.


## Isolating internal from external components &  Handling HTTPS termination: Traefik Ingress controller.

As with the monitoring solution (more on that below), there's an operator for Traefik that installs the whole thing. But it proved more difficult to set up and configure than finding appropriate Kubernetes definitions files and applying those, after careful modification.

As always: it's a balancing act between costs and benefits, and for this test my time was scarce and the complexity required is low.

### HTTPS Termination. Provided by Ingress!

Exposing 2 routers for each of the internet exposed services, but both leading to the same insecure port/entrypoint, we try to have Traefik do the TLS termination. Traefik would "listen" for requirements in both secure and insecure ports, and the rest of the services "inside" can very well work without needing to secure their traffic against the end user.

I do understand this may not be ideal, as the Ingress controller now becomes a single point of failure, regarding security. A vector of attack, dare I say. And, as I mentioned before, I'd take a look into trust technologies for micro-services like Spiffe.

Full disclosure: didn't know that SSL Termination was until this project. I understand what it is now, and I think that if I actually created certificates it would work (with some more tweaking I'm sure, just don't have a lot of experience on it yet)


## A schedule for backups and a disaster recovery plan: Back ups and recovery

There seems to be a general consensus that pg_dump'ing the database on a periodical basis produces adequate backups for databases that are not too big or too critical. But, given that scenario, I would add and leverage PostgreSQL's Point In Time Recovery functionalities. I'd check into pgbarman for this.

Sometimes, recovery times that are measured in hours to days are not acceptable for business (sounds crazy, but I work @ gov, and sometimes it actually is acceptable) make the strategy of full dumps unusable in the day-to-day, and smaller and more faster updates are needed. That's why I propose doing both kinds of back ups. A full strategy involves many factors, but as a rule of thumb: weekly full dumps and daily incrementals work great at some lines of work and companies. For fast-paced online companies (like Balena?) a daily full and incrementals every few minutes could be more suitable.

On the cloud side of database hosting, cloud vendors offer tools that ease very much this burden. From AWS offering: "Amazon RDS Backup and Restore
By default, Amazon RDS creates and saves automated backups of your DB instance securely in Amazon S3 for a user-specified retention period. In addition, you can create snapshots, which are user-initiated backups of your instance that are kept until you explicitly delete them."

In my experience, Incrementals tend to take 2% to 5% the size of the full, so allotting/planning for 150 to 175% of the full data is not unheard of, depending on the distance between full dumps.

On both sides: a disaster recovery plan would have to be thoroughly outlined and frequently tested by all parties involved. Having the whole infrastructure and application code committed to code ensures a recovery as painless as it can be done. And the anti-fragility mindset that emerges from the SRE practices is a great tool for that. (The whole cycle of things breaking, fixing, testing, monitoring)

To me, that means that everybody involved is to be aware of the implications of changes made (to both infra and apps) outside of the central repository of code (GIT!), and to keep it as the whole and only source of truth in the company. The R in SRE stands for Reliability, but all parties involved contribute to that.

There's a mantra in back ups that says: "_The time and effort to make a backup is inversely proportional to the time and effort that will take to restore from it_". I like to thing that the DevOps practices aim to spread that concept to every other part of the development chain.

And finally: Just as redundancy is not backup, well, backup is not redundancy either. I touch the redundancy topic in a following section.


## An overview of performance metrics that you'd collect from the system 

A few ideas:

* Most frequently used HTTP endpoints
* Slowest HTTP endpoints
* Average Connection time
* Error Status Codes
* Service response time
* Service availability up/down
* Running/desired replicas ratio. A low value for some extension of time is a symptom of something not working properly (not enough nodes or resources available, Kubernetes or Docker Engine failure, Docker image broken, etc).
* Replicas below threshold. (zero replicas is probably a problem)
* Nodes/infrastructure: hardware utilization (memory and storage usage: capacity planning) and general maintenance. Up/Down status.
* Restart loops and CrashLoopBackOff states. Any non-zero value is an issue to look at.
* SLA compliance 
* Successful / error requests per second

### Monitoring

I deployed a Prometheus service as requested. A more complete solution would have been kube-prometheus https://github.com/coreos/kube-prometheus, but a little over the top for such a small project (I even got it to work, but it's too much of a hassle for empty graphs, and this project got too large already). And setting up Prometheus "manually" was not difficult at all (setting up a service and a config map, as easy as it gets).

Once the Prometheus pods and service are running, it can be tested loading http://prometheus.secretid:9090/ and querying "prometheus_target_interval_length_seconds", for example, or heading to http://prometheus.secretid:9090/targets.

#### Metrics:

In order to have some metrics to prove the thing works, I embedded the example for the library I used in the web service (https://pypi.org/project/prometheus-flask-exporter/) into the very code of the app.

A more kubernetes-like way would be to employ the sidecar pattern and add sidecar containers to expose and convert metrics. This https://github.com/wrouesnel/postgres_exporter one for postgres comes to mind.



*What* did I do, and *Why*
===========================

### Kubernetes

Installing Kubernetes over vagrant/VirtualBox machines imposes some challenges:

Kubeadm insists on setting the default network interface as the one bound to the default route. And VirtualBox offers some choices for the networking, but it must be one that allows the nodes to connect to the Internet. After some problems and debug, I set the (virtual machine!) nodes to connect with my home network and set the default route towards my home router. Fixed IPs, but that's yet for another reason =/

On a real world installation this would not be an issue: on a managed solution this would be transparent. On a self-managed solution (hosted on-prem or on cloud) the first interface will not be the 10.0.2.15 private interface from VirtualBox, but a real interface used to configure the rest of the node.


### Database

Since this service is super simple, I did not made any provisions to allow modification of it. I could have done it programatically too, but this project is big enough as it is (^\_^)

The database is copied via Ansible, straight into the NFS server service folder; after the k8s cluster initialization and before the database pod and service spin-up.

Another way to do it would have been leveraging an initialization pod, within Kubernetes capabilities.



### NFS

The database is hosted outside the Kubernetes cluster. When pods go belly up they take their storage with them, so it must be hosted outside any pods and served some way to the database pod. I chose NFS to do it, tried and tested industry standard.

The NFS share could use some more security: this application only needs Read-Only access. And the hosts allowed by /etc/exports file is static (new members added to the cluster would have to be added and the whole NFS service reloaded). The easiest solution would be IMHO using a promiscuous NFS server and securing it on another layer. (iptables on the node, "firewall" (network rules) on the Kubernetes cluster level, SE-Linux... and I definitely would take a look at Spiffe - https://spiffe.io/)

The NFS mount is shared across all the members of the cluster, yet we are only defining a single database server. The reason for that is that we let the cluster decide where to host the database pod, within it's knowledge of the resources. If we were to spin up replicas (more on that later), we would need more NSF servers and shares: NFS is not a multi-user filesystem! (<meme>You want database corruption? Because that's how you get database corruption</meme>)
Although, maybe, a database server acting as a slave could use the same directory (NSF mount), but there would not be any actual replication and, therefore, no high availability.

I chose to setup an NSF server. In a real world scenario, I see no use in reinventing the wheel and would trust a storage solution from the cloud provider.  (Or not! The criteria to chose one or the other would be: feature set, performance, cost, reliability and ease of maintenance. The very same thing applies to the database hosting and management.). The GCP calculator comes back for around $200/mo for 10TB on their Cloud Storage service. At that price range and storage size, I see no point on in hosting the data myself.

### Redundancy

There is no redundancy for the NFS share and database files so far in this solution. There are numerous ways to achieve that:
* Block and filesystem level redundancy: Storing the actual data over DRBD clustering, Ceph, OCFS2...
* Service level redundancy: NFS HA. Or maybe switching to a file server service that actually is replicated? GlusterFS comes to mind.
* Cloud level: not experienced enough to have an opinion, but I suspect it could be a heavy contender and cost efficient while at it, too.
* Database level redundancy: Postgres (in this scenario) mirroring over multiple NFS shares.

Given that we are not interested in mere mirroring or HA, but actual data consistency, I'd start looking with the latter.

### Images

Docker images are distributed through Ansible to the hosts to build. This is less than ideal. A more wholesome approach would be to shift the burden of an actual registry, or maybe leveraging Kubernetes facilities to copy the application data to the containers on pod creation or startup.

### Vagrant

After the 4th cluster rebuild from scratch, it gets tiresome to download the packages again. Added a shared folder on the Vagrantfile, pointed at "/var/cache/apt/archives" to save the cache across runs.

In order to avoid the Kubernetes routing issue mentioned before, I had to resort to put the nodes into my own network. There is an always running provisioner that switches the default route every time the nodes boot.

#### Sources of info and links

on Kubernetes

[kubectl Cheat Sheet - Kubernetes](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
[franciscofregona/kubernetes-cluster: Kubernetes cluster using Vagrant, VirtualBox and Kubeadm](https://github.com/franciscofregona/kubernetes-cluster)
[k8s – Manage Kubernetes (K8s) objects @ Ansible Documentation](https://docs.ansible.com/ansible/latest/modules/k8s_module.html#k8s-raw-module)
[Multi Node Kubernetes Cluster with Vagrant, VirtualBox and Kubeadm](https://medium.com/@wso2tech/multi-node-kubernetes-cluster-with-vagrant-virtualbox-and-kubeadm-9d3eaac28b98)
[Installing a Registry on Kubernetes (Quickstart)](https://blog.container-solutions.com/installing-a-registry-on-kubernetes-quickstart)
[Install Traefik @ Traefik](https://docs.traefik.io/getting-started/install-traefik/)
[Ingress @ Kubernetes](https://kubernetes.io/docs/concepts/services-networking/ingress/)
[Service @ Kubernetes](https://kubernetes.io/docs/concepts/services-networking/service/)
[Sharing an NFS PV Across Two Pods @ OKD Latest](https://docs.okd.io/latest/install_config/storage_examples/shared_storage.html)
[Debugging DNS Resolution @ Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)
[Deploying Calico and Kubernetes on Container Linux by CoreOS using Vagrant and VirtualBox](https://docs.projectcalico.org/v3.0/getting-started/kubernetes/installation/vagrant/)
[Understanding kubernetes networking: pods - Google Cloud Platform - Community - Medium](https://medium.com/google-cloud/understanding-kubernetes-networking-pods-7117dd28727)
[Deployments - Kubernetes](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#creating-a-deployment)
[Configuring Container Capabilities with Kubernetes](https://www.weave.works/blog/container-capabilities-kubernetes/)
[Kubernetes CRD  Traefik](https://docs.traefik.io/reference/dynamic-configuration/kubernetes-crd/)
[How to install and configure traefik in kubernetes helm](https://8gwifi.org/docs/kube-traefik.jsp)

On Monitoring

[Monitoring Kubernetes with Prometheus](https://sysdig.com/blog/kubernetes-monitoring-prometheus/)
[Prometheus github page - Getting Started](https://github.com/prometheus/prometheus/blob/master/docs/getting_started.md)
[ConfigMaps @ Kubernetes.io](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
[Kubernetes mount file @ CarlosMendible.com](https://carlos.mendible.com/2019/02/10/kubernetes-mount-file-pod-with-configmap/)

On Databases

[CrunchyData/postgres-operator: PostgreSQL Operator Creates/Configures/Manages PostgreSQL Clusters on Kubernetes](https://github.com/CrunchyData/postgres-operator)
[How to replicate PostgreSQL Database as Master/Slave](https://coderbook.com/@marcus/how-to-replicate-postgresql-database-as-masterslave/)
[Import CSV File Into PosgreSQL Table](http://www.postgresqltutorial.com/import-csv-file-into-posgresql-table/)
[To run or not to run a database on Kubernetes @ Google Cloud Blog](https://cloud.google.com/blog/products/databases/to-run-or-not-to-run-a-database-on-kubernetes-what-to-consider)
[Python bindings @ PostgreSQL wiki](https://wiki.postgresql.org/wiki/Python)
[Kubernetes probes for PostgreSQL pods @ Niel de Wet - Medium](https://medium.com/@nieldw/kubernetes-probes-for-postgresql-pods-a66d707df6b4)
[Kubernetes Volumes Guide – Examples for NFS and Persistent Volume](https://matthewpalmer.net/kubernetes-app-developer/articles/kubernetes-volumes-example-nfs-persistent-volume.html)
[Using Kubernetes Persistent Volumes](https://coderjourney.com/using-kubernetes-persistent-volumes/)
[chown: changing ownership of ‘/var/lib/postgresql/data’· Issue #54601](https://github.com/kubernetes/kubernetes/issues/54601)
[chown: changing ownership of /data/db @ Stack Overflow](https://stackoverflow.com/questions/51200115/chown-changing-ownership-of-data-db-operation-not-permitted)
[postgres @ Docker Hub](https://hub.docker.com/_/postgres)
[PostgreSQL 9.3.25 Documentation](https://www.postgresql.org/docs/9.3/app-pgdump.html)
[Managing PostgreSQL backup and replication for very large databases @ Leboncoin Blog](https://medium.com/leboncoin-engineering-blog/managing-postgresql-backup-and-replication-for-very-large-databases-61fb36e815a0)
[PostgreSQL hot backups with barman.](https://www.pgbarman.org/)

On Images and REST

[Consuming Web APIs with Python @ ITNEXT](https://itnext.io/consuming-web-apis-with-python-fa9b751d2c75)
[Consuming a RESTful API with Python and Flask](https://www.restapiexample.com/python/consuming-a-restful-api-with-python-and-flask/)
[Running Your Flask Application Over HTTPS @ miguelgrinberg.com](https://blog.miguelgrinberg.com/post/running-your-flask-application-over-https)
[Create a web application with python + Flask + PostgreSQL and deploy on Heroku](https://medium.com/@dushan14/create-a-web-application-with-python-flask-postgresql-and-deploy-on-heroku-243d548335cc)
[tiangolo/full-stack-fastapi-postgresql: Full stack, modern web application generator. Using FastAPI, PostgreSQL as database, Docker, automatic HTTPS and more.](https://github.com/tiangolo/full-stack-fastapi-postgresql)
[jazzdd/alpine-flask - Docker Hub](https://hub.docker.com/r/jazzdd/alpine-flask/)

BUGS
====

* Fixed. Bug on my provisioner code.~~Sometimes the VMs are not correctly provisioned during the 'vagrant up' command. Workaround: create all of them with 'vagrant up --no-provision' and execute 'vagrant provision' afterwards.~~

* Failure at getting the web for any service:
Symptom:
```bash
curl web.secretid:8000/
```
Gets ``curl: (52) Empty reply from server``

**Reason**: If the web and API services are recreated but the forward_ports script is not killed and relaunched, it tries to use stale pods.

**Solution**: A more elaborate script is called for. I'd create a PID file to ensure restarting it effectively. In the meantime, on the head node:

```bash
ps -A | grep kubectl 				#Found the kubectl instances running.
```

``29776 pts/0    00:00:00 kubectl		#Found only one instance. In case there are more, or just to check...``

```bash
cat /proc/29776/cmdline					#see what is it that it is running
```

``kubectlport-forward--address0.0.0.0service/secretid8000:80008080:80804443:4443-ndefault``
 (mangled cmdline used to invoke it. This is the one!)

```bash
kill -9 29776							#We all saw this coming...
forward_ports.sh						#and relaunch
```

### Code and credits

* The vagrantfile is a repo by https://github.com/ecomm-integration-ballerina/kubernetes-cluster, modified afterwards by me.
* The Ansible roles and bash scripts are all mine.
* The rest of the code is copypasta from the links in this file, mostly tutorials and official doc.

## TODO

- [ ] Important: ACTUAL CERTIFICATE AND ENCRYPTION
- [ ] Actual testing. This got too big already, but it ain't complete without tests. Kubernetes declarative syntax is nice and all but...
- [ ] Vagrantfile refactor. The provisioners should be ported to Ansible and variables defined in a single place. It will do for now but needs refactoring.
- [ ] Fix Hard-Coded variables in Vagrantfile
- [ ] Fix Hard-Coded variables in dbPersVolume.yml
- [ ] Ansible roles need refactorization: Hard coded variables everywhere. Good enough for a take-away though.
- [ ] Ansible roles readmes.
- [ ] Ansible role "loaddatabase" ended up too skinny. Needs to regain the copy of the data or be taken down entirely.
- [x] README y TODO
- [x] Add a dbDeployment and remove dbPod.
- [x] Check for the environment variables asked for
- [x] add postgres password and database name as variables. And secrets, too.
- [x] URLs of the services as variables.
- [x] Put the code outside the container and fetch it as first operation. Or fetch it as last operation in the Dockerfile.
