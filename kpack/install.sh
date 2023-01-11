#!/bin/sh

set -e

CURR_DIR=$(dirname $0)
devNamespace="dev"
testImageTag="hello-spring-boot"

printf -- "Enter the kpack version you want to install (you can find the latest version at https://github.com/pivotal/kpack/releases/latest):\n"
read kpackVersion
printf -- "Enter your container registry. You need to have write permissions. (e.g. \"my-harbor.acme.org/my-project\"):\n"
read containerImageRegistry
printf -- "Container registry username:\n"
read username
printf -- "Container registry password:\n"
read -s password

printf -- "\033[2m"
kubectl apply -f https://github.com/pivotal/kpack/releases/download/v$kpackVersion/release-$kpackVersion.yaml

REGISTRY_PASSWORD=$password kp secret create builder-image-registry-credentials \
    --registry $containerImageRegistry \
    --registry-user $username \
    --namespace kpack

printf -- "\033[0mConfiguring kpack\033[2m\n"
builderImageTagFqdn="$containerImageRegistry/kpack/default-builder"
sed s#BUILDER-TAG#$builderImageTagFqdn#g $CURR_DIR/configuration.yaml | kubectl apply -f - #use hash as command separator since the image tag contains slashes
# Let's wait for kpack-webhook to become available, otherwise kpack image create command will end up waiting undefinitely
kubectl -n kpack wait --for=condition=Available deployment/kpack-webhook --timeout=60s


printf -- "\033[0mCreating $devNamespace namespace\033[2m\n"

kubectl create ns $devNamespace

REGISTRY_PASSWORD=$password kp secret create registry-credentials \
    --registry $containerImageRegistry \
    --registry-user $username \
    --namespace $devNamespace

sed s#DEV-NAMESPACE#$devNamespace#g $CURR_DIR/dev-serviceaccount.yaml |kubectl apply -f -

while true; do
    printf -- "\033[0mDo you wish to run a kpack smoke test? (y)Yes/(n)No: "
    read runSmokeTest
    case $runSmokeTest in
        [Yy]* )
            printf -- "\033[0mExecuting smoke test (this could take some minutes)\033[2m\n"
            smokeTestImageFqdn=$containerRegistry/$repositoryNamespace/$testImageTag
            kp image create kpack-smoke-test \
                --tag $containerImageRegistry/$testImageTag \
                --git https://github.com/lorisp1/hello-spring-boot.git \
                --env BP_JVM_VERSION=19 \
                --git-revision master \
                --service-account dev-sa \
                --cluster-builder default \
                --namespace $devNamespace \
                --wait

            printf -- "\033[0mDeploying the smoke test application to the k8s cluster\033[2m\n"
            kubectl run kpack-smoke-test \
                --image=$containerImageRegistry/$testImageTag \
                --restart=Never \
                --namespace=$devNamespace
            kubectl expose pod kpack-smoke-test \
                --port 8080 \
                --target-port 8080 \
                --namespace=$devNamespace

            printf -- "\033[0mWaiting for the test container to become ready\033[2m\n"
            kubectl wait --for=condition=Ready pod/kpack-smoke-test --timeout=-1s --namespace=$devNamespace
            printf -- "\n"
            kubectl run kpack-smoke-test-client --image=busybox -it --restart=Never --namespace=$devNamespace -- wget -q -O- kpack-smoke-test:8080
            printf -- "\n"

            printf -- "\033[0mCleaning up..\033[2m\n"
            kubectl -n $devNamespace delete pod kpack-smoke-test-client kpack-smoke-test
            kubectl -n $devNamespace delete service kpack-smoke-test
            kp -n $devNamespace image delete kpack-smoke-test
            printf -- "\033[0m"
            break;;
        [Nn]* ) break;;
        * ) printf -- "\033[0mPlease answer yes or no\033[2m";;
    esac
done

