# #Forward Prometheus port
kubectl port-forward --address 0.0.0.0 $(kubectl get pods --selector=app=prometheus --output=jsonpath="{.items[0]..metadata.name}")  9090
# #Forward Grafana port
# kubectl port-forward --address 0.0.0.0 $(kubectl get pods --selector=app=grafana --output=jsonpath="{.items..metadata.name}")  3000 &
# #Forward AlertManager port
# kubectl port-forward --address 0.0.0.0 svc/alertmanager-main  9093 &
