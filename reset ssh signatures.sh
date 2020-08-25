#Every time we tear down and rebuild the cluster, its SSH signatures change.
#This handy time saver fixes that. Definitely not for production =)
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "192.168.100.110"
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "192.168.100.111"
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "192.168.100.112"
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "192.168.100.119"
ssh-keyscan -H 192.168.100.110 >> ~/.ssh/known_hosts
ssh-keyscan -H 192.168.100.111 >> ~/.ssh/known_hosts
ssh-keyscan -H 192.168.100.112 >> ~/.ssh/known_hosts
ssh-keyscan -H 192.168.100.119 >> ~/.ssh/known_hosts