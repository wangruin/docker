set -e
curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

IMAGE_NAME_TOOLCHAIN='toolchain'
IMAGE_NAME_THIRDPARTY='dev-env'

source $curdir/params.sh

RUNNING=$(docker ps -a | grep $CONTAINER_NAME_TOOLCHAIN || echo 0)
if [ ${#RUNNING} != 1 ]; then
    echo "======= $CONTAINER_NAME_TOOLCHAIN is exist."
    exit 1
else 
    echo "======= $CONTAINER_NAME_TOOLCHAIN will run."
fi

wget -O java.tar.gz "$JDK_SOURCE"
if [[ ! -f "java.tar.gz" ]]; then
    echo "java.tar.gz found"
    exit 1
fi

wget -O cmake.tar "$CMAKE_SOURCE"
rm -rf cmake && mkdir cmake && tar -xvf cmake.tar -C cmake --strip-components 1
rm -rf cmake.tar


# build toolchain
echo "========== start to build $IMAGE_NAME_TOOLCHAIN..."
rm -rf sr-toolchain/starrocks

git clone -b $GIT_BRANCH $GIT_REPO sr-toolchain/starrocks

if [[ ! -d "sr-toolchain/starrocks" ]]; then  
    echo "starrocks not found"
    exit 1
fi 

if [[ ! -f "sr-toolchain/starrocks/thirdparty/vars.sh" ]]; then
    echo "vars.sh not found"
    exit 1
fi

cp java.tar.gz sr-toolchain/
if [[ ! -f "sr-toolchain/java.tar.gz" ]]; then
    echo "jdk not found"
    exit 1
fi

cp -r cmake sr-toolchain/
cp install_env_gcc.sh sr-toolchain/
cp install_java.sh sr-toolchain/

copy_num=$(sed -n  '/===== Downloading thirdparty archives...done/=' sr-toolchain/starrocks/thirdparty/download-thirdparty.sh)
if [[ copy_num == 0 ]]; then
    echo "===== cannot generate download scripts"
    exit 1
fi
head -n $copy_num sr-toolchain/starrocks/thirdparty/download-thirdparty.sh > sr-toolchain/starrocks/thirdparty/download-for-docker-thirdparty.sh

echo '========== download thirdparty src...'
bash sr-toolchain/starrocks/thirdparty/download-for-docker-thirdparty.sh

cd sr-toolchain
docker build \
-t starrocks/$IMAGE_NAME_TOOLCHAIN:$IMAGE_VERSION \
--build-arg GCC_VERSION=$GCC_VERSION \
--build-arg GCC_URL=$GCC_URL \
--build-arg MAVEN_VERSION=$MAVEN_VERSION \
--build-arg SHA=$SHA \
--build-arg BASE_URL=$BASE_URL .

echo "========== build $IMAGE_NAME_TOOLCHAIN... done"

echo "========== start $CONTAINER_NAME_TOOLCHAIN..."
docker run -it --name $CONTAINER_NAME_TOOLCHAIN -d starrocks/$IMAGE_NAME_TOOLCHAIN:$IMAGE_VERSION

echo "========== start to build thirdparty..."

docker exec -it $CONTAINER_NAME_TOOLCHAIN /bin/bash /var/local/install.sh

echo "========== start to transfer thirdparty..."
docker cp $CONTAINER_NAME_TOOLCHAIN:/var/local/thirdparty ../sr-thirdparty/
rm -rf jdk.rpm

cd ..

cp java.tar.gz sr-thirdparty/
if [[ ! -f "sr-thirdparty/java.tar.gz" ]]; then
    echo "jdk not found"
    exit 1
fi

cp -r cmake sr-thirdparty/
cp install_env_gcc.sh sr-thirdparty/
cp install_java.sh sr-thirdparty/

# build thirdparty
cd sr-thirdparty
if [[ ! -d "thirdparty" ]]; then
    echo "thirdparty not found"
    exit 1
fi
rm -rf thirdparty/src

mkdir -p llvm/bin && cp /home/disk1/doris-deps/toolchain/installed/llvm-10.0.1/bin/clang-format llvm/bin

docker cp $CONTAINER_NAME_TOOLCHAIN:/usr/share/maven ../sr-thirdparty/

echo "========== start to build $IMAGE_NAME_THIRDPARTY..."

docker build -t starrocks/$IMAGE_NAME_THIRDPARTY:$GIT_BRANCH-$IMAGE_VERSION \
--build-arg GCC_VERSION=$GCC_VERSION \
--build-arg GCC_URL=$GCC_URL .

echo "========== build $IMAGE_NAME_THIRDPARTY done..."
