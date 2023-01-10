#!/bin/sh

set -e

devNamespace="dev"
testImageTag="hello-spring-boot"

echo "This script will setup kpack on the current Kubernetes context in a \"kpack\" namespace, then it will setup a $devNamespace namespace"
echo "For the prerequisites, please refer to https://github.com/pivotal/kpack/blob/main/docs/install.md"
echo "After installing and configuring kpack, the script will launch an image build as a smoke test. For this purpose, you should have kp CLI installed."
echo ""

echo "Enter the kpack version you want to install (you can find the latest version at https://github.com/pivotal/kpack/releases/latest)"
read kpackVersion
echo "Enter your container registry. You need to have write permissions. (e.g. \"my-harbor.acme.org/my-project\"):"
read containerImageRegistry
echo "Container registry username:"
read username
echo "Container registry password:"
read -s password

echo "Installing kpack"
kubectl apply -f https://github.com/pivotal/kpack/releases/download/v$kpackVersion/release-$kpackVersion.yaml

REGISTRY_PASSWORD=$password kp secret create builder-image-registry-credentials \
    --registry $containerImageRegistry \
    --registry-user $username \
    --namespace kpack

echo "Configuring kpack"
builderImageTagFqdn="$containerImageRegistry/kpack/default-builder"
sed s#BUILDER-TAG#$builderImageTagFqdn#g configuration.yaml | kubectl apply -f - #use hash as command separator since the image tag contains slashes
# Let's wait for kpack-webhook to become available, otherwise kpack image create command will end up waiting undefinitely
kubectl -n kpack wait --for=condition=Available deployment/kpack-webhook --timeout=60s


echo "Creating $devNamespace namespace"

kubectl create ns $devNamespace

REGISTRY_PASSWORD=$password kp secret create registry-credentials \
    --registry $containerImageRegistry \
    --registry-user $username \
    --namespace $devNamespace

sed s#DEV-NAMESPACE#$devNamespace#g dev-serviceaccount.yaml |kubectl apply -f -

while true; do
    read -p "Do you wish to run a kpack smoke test? (y)Yes/(n)No: " runSmokeTest
    case $runSmokeTest in
        [Yy]* )
            echo "Executing smoke test (this could take some minutes)"
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

            echo "Deploying the smoke test application to the k8s cluster"
            kubectl run kpack-smoke-test \
    --image=$containerImageRegistry/$testImageTag \
                --restart=Never \
                --namespace=$devNamespace
            kubectl expose pod kpack-smoke-test --port 8080 --target-port 8080 --namespace=$devNamespace

            echo "Waiting for the test container to become ready"
            kubectl wait --for=condition=Ready pod/kpack-smoke-test --timeout=-1s --namespace=$devNamespace
            echo ""
            kubectl run kpack-smoke-test-client --image=busybox -it --restart=Never --namespace=$devNamespace -- wget -q -O- kpack-smoke-test:8080
            echo ""

            echo "Cleaning up.."
            kubectl -n $devNamespace delete pod kpack-smoke-test-client kpack-smoke-test
            kubectl -n $devNamespace delete service kpack-smoke-test
            kp -n $devNamespace image delete kpack-smoke-test 
            break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no";;
    esac
done

echo "Done!"