#Forward ports for HTTP, HTTPS
kubectl port-forward --address 0.0.0.0 service/traefik 80:8000 443:4443