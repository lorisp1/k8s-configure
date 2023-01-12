#!/bin/sh

set -e

printf -- "This script will install Jenkins and Kpack on the current Kubernetes cluster.\n"
printf -- "Requirements:\n"
printf -- "\t- \033[1mMinikube \033[0mrunning Kubernetes >= 1.22, with cluster-admin permissions for the current user\n"
printf -- "\t- \033[1mHarbor \033[0mregistry with a user having write privileges\n"
printf -- "\t- kubectl CLI\n"
printf -- "\t- kp CLI\n"

while true; do
    read -p "Continue? (y)Yes/(n)No: " yn
    case $yn in
        [Yy]* )
            minikubeProfile=$(kubectl config current-context)

            printf -- "==================\n"
            printf -- " Enabling metrics \n"
            printf -- "==================\n"
            printf -- "\033[2m"
            minikube addons enable metrics-server -p $minikubeProfile
            printf -- "\033[0m\033[32mDONE!\033[0m\n"
            printf -- "====================\n"
            printf -- " Installing Jenkins \n"
            printf -- "====================\n"
            ./jenkins/install.sh
            printf -- "\033[0m\033[32mDONE!\033[0m\n"

            printf -- "====================\n"
            printf -- "  Installing Kpack  \n"
            printf -- "====================\n"
            ./kpack/install.sh
            printf -- "\033[0m\033[32mDONE!\033[0m\n"
            break;;
        [Nn]* ) break;;
        * ) printf -- "Please answer yes or no\n";;
    esac
done