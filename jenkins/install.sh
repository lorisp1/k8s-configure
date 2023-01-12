#!/bin/sh

set -e
CURR_DIR=$(dirname $0)
JENKINS_HOST="jenkins.minikube"

printf -- "\033[2m"
helm repo add jenkinsci https://charts.jenkins.io
helm repo update


kubectl create ns jenkins
kubectl apply -f $CURR_DIR/jenkins-sa.yaml
kubectl apply -f $CURR_DIR/jenkins-pv.yaml

minikubeProfile=$(kubectl config current-context)
minikube ssh -p $minikubeProfile 'sudo mkdir -p /data/jenkins-volume && sudo chown -R 1000:1000 /data/jenkins-volume'

helm install jenkins -n jenkins -f $CURR_DIR/jenkins-values.yaml jenkinsci/jenkins
printf -- "\033[0mWaiting for Jenkins to be ready (this could take some minutes)\033[2m\n"
kubectl -n jenkins wait --for=condition=Ready pod/jenkins-0 --timeout=-1s

printf -- "\033[0mConfiguring Jenkins ingress\033[2m\n"
sed s/JENKINS_HOST/$JENKINS_HOST/g $CURR_DIR/ingress.yaml |kubectl apply -f -

jenkinsIp=$(kubectl get nodes --namespace jenkins -o jsonpath="{.items[0].status.addresses[0].address}")
jenkinsPort=$(kubectl get --namespace jenkins -o jsonpath="{.spec.ports[0].nodePort}" services jenkins)
adminPassword=$(kubectl exec --namespace jenkins -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password)
printf -- "\033[0mInstallation complete\n"
printf -- "\t- Jenkins URL:\thttp://$JENKINS_HOST\n"
printf -- "\t- Username:\tadmin\n"
printf -- "\t- Password:\t$adminPassword\n"
printf -- "Please copy the following information and press ENTER when ready"
read