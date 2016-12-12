# Issues Todos

## next issues
* get newly successfully build docker hub images of all installed docker images
  * explore dockerhub api
  * what happens when a dockerhub build fails
* delete unused docker containers
  * based on access log
* write access log
* compare medium to high load to nginx or native implementation
* add label to automatically created containers in order to know which ones can be deleted
* handle failure of request to container with http status code response
* handle special request (e.g. /metrics, /logs ..) directly by servcie script
* add trace id to request
* inject source ip and port into headers when forwarding request into container
* inject set of environment variables into newly created containers
* add possiblity to inject debug flag with request headers
* containers should be able to send requests to dynamic load without using public address:port
  * maybe by using a docker network
* is it possible to know how many requests are currently active based on the access logs
* create systemd startup script
* is it possible to execute script with limited nobody user but still launch docker containers

## other issues
* http form to facilitate query parameter entry
  * generic creation of http form based on output from script 



