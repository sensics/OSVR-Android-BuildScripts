#!/bin/bash -e
export SCRIPTSDIR=$(cd $(dirname $(readlink --canonicalize $0)) && pwd)
export SCRIPTSDIRNAME=$(basename ${SCRIPTSDIR})
export ROOT=$(cd $(dirname $(readlink --canonicalize $0)) && cd .. && pwd)
if [ -f ${ROOT}/opts.sh ]; then
    echo "Loading options from ${ROOT}/opts.sh"
    source ${ROOT}/opts.sh
fi

# These variables may be overridden/set by the environment, or, more preferably,
# by a line in opts.sh
export CMAKE="${CMAKE:-cmake}"
export GENERATOR="${GENERATOR:-Ninja}"
export ANDROID_PLATFORM=${ANDROID_PLATFORM:-android-24}
export ANDROID_NDK="${ANDROID_NDK}"
export BUILD=${BUILD:-${ROOT}/build}
export CONFIG=${CONFIG:-Release}
export ANDROID_ABI=${ANDROID_ABI:-armeabi-v7a}
export INSTALL=${INSTALL:-${BUILD}/${ANDROID_ABI}/install}
export HOST_INSTALL=${INSTALL:-${BUILD}/host/install}
export SHOULD_CONFIGURE=${SHOULD_CONFIGURE:-true}

if [ "${ANDROID_NDK}" == "" ]; then
    echo "Must run or add the following to opts.sh: export ANDROID_NDK=/path/to/your/android/ndk"
    exit 1
fi

export BOOST_VER=1.65.1
export BOOST_FN=boost_${BOOST_VER//./_}.tar.bz2
export BOOST_URL=https://dl.bintray.com/boostorg/release/${BOOST_VER}/source/${BOOST_FN}
export TARGET_CMAKE_PREFIX_PATH=${INSTALL} 

OPENCV_VERSION=2.4.11
OPENCV_SHA1=ACFB4789B78752AE5C52CC5C151E2AE3DD006CEF
OPENCV_FN=OpenCV-${OPENCV_VERSION}-android-sdk.zip
OPENCV_URL=http://downloads.sourceforge.net/project/opencvlibrary/opencv-android/${OPENCV_VERSION}/${OPENCV_FN}

### Generic Helper Functions
target_build_dir() {
    echo ${BUILD}/${ANDROID_ABI}/${1}
}
host_build_dir() {
    echo ${BUILD}/host/${1}
}
target_cmake_build() {
    project=$1
    shift
    src=$(cd $1 && pwd)
    shift
    build=$(target_build_dir $project)
    echo -e "[Target]\t CMake build of ${project} with:"
    echo "   source: ${src}"
    echo "   build:  ${build}"
    mkdir -p "${build}" 
    (
        cd "${build}"
        set -x
        if $SHOULD_CONFIGURE; then
            ${CMAKE} ${EXTRA_CMAKE_ARGS} \
                -G "${GENERATOR}" \
                -DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK}/build/cmake/android.toolchain.cmake \
                -DANDROID_TOOLCHAIN=clang \
                -DANDROID_STL=c++_shared \
                "-DANDROID_ABI=${ANDROID_ABI}" \
                -DANDROID_PLATFORM=${ANDROID_PLATFORM} \
                -DANDROID_CPP_FEATURES="rtti;exceptions" \
                -DCMAKE_INSTALL_PREFIX=${INSTALL} \
                -DCMAKE_FIND_ROOT_PATH=${INSTALL} \
                -DCMAKE_PREFIX_PATH="${TARGET_CMAKE_PREFIX_PATH}" \
                -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
                -DCMAKE_BUILD_TYPE=${CONFIG} \
                ${TARGET_CMAKE_ARGS} \
                "$@" \
                ${src}
        fi
        ${CMAKE} --build .
        ${CMAKE} --build . --target install
        set +x
    )
}
append_project_config_to_cmake() {
    project=$1
    # if [ "${CMAKE_MODULE_PATH}" ]; then
    #     CMAKE_MODULE_PATH="${CMAKE_MODULE_PATH};"
    # fi
    # export CMAKE_MODULE_PATH="${CMAKE_MODULE_PATH}${INSTALL}/lib/cmake/$project"
    export TARGET_CMAKE_PREFIX_PATH="${TARGET_CMAKE_PREFIX_PATH};${INSTALL}/lib/cmake/$project"
}

append_dir_to_cmake() {
    export TARGET_CMAKE_PREFIX_PATH="${TARGET_CMAKE_PREFIX_PATH};${1}"
}

append_to_cmake_args() {
    export TARGET_CMAKE_ARGS="${TARGET_CMAKE_ARGS} ${1}"
}
host_cmake_build() {
    project=$1
    shift
    src=$(cd $1 && pwd)
    shift
    build=$(host_build_dir $project)
    echo -e "[Host]\t CMake build of ${project} with:"
    echo "   source: ${src}"
    echo "   build:  ${build}"
    mkdir -p "${build}" 
    (
        cd "${build}"
        set -x
        if $SHOULD_CONFIGURE; then
            ${CMAKE} ${EXTRA_CMAKE_ARGS} \
                -G "${GENERATOR}" \
                -DCMAKE_INSTALL_PREFIX=${HOST_INSTALL} \
                -DCMAKE_PREFIX_PATH=${HOST_INSTALL} \
                -DCMAKE_BUILD_TYPE=${CONFIG} \
                "$@" \
                ${src}
        fi
        ${CMAKE} --build .
        ${CMAKE} --build . --target install
        set +x
    )
}
target_ndk_build() {
    project=$1
    shift
    src=$(cd $1 && pwd)
    shift
    build=$(target_build_dir ${project})
    echo -e "[Target]\t ndk-build of ${project} with:"
    echo "   source: ${src}"
    echo "   build:  ${build}"
    mkdir -p "${build}" 
    (
        set -x
        ${ANDROID_NDK}/ndk-build \
            APP_ABI=${ANDROID_ABI} \
            "NDK_OUT=${build}" \
            "NDK_APP_DST_DIR=${INSTALL}/lib" \
            "$@" -C ${src}
        set +x
    )
}

### Project Builds
unpack_opencv() {
    mkdir -p ${BUILD}/OpenCV
    cd ${BUILD}/OpenCV
    wget --timestamping ${OPENCV_URL} && unzip ${OPENCV_FN} || echo "Already up to date."
}
build_osvr_json_to_c() {
    if [ ! "${OSVR_JSON_TO_C}" ]; then
        host_cmake_build jsoncpp src/jsoncpp \
            -DJSONCPP_WITH_CMAKE_PACKAGE=ON \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_STATIC_LIBS=ON \
            -DJSONCPP_WITH_TESTS=OFF \
            -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF
        host_cmake_build osvr_json_to_c buildscripts/osvr_json_to_c \
            -DOSVR_CORE_SOURCE_DIR=${ROOT}/src/OSVR-Core

        export OSVR_JSON_TO_C=${HOST_INSTALL}/bin/osvr_json_to_c
    fi
}

build_jsoncpp() {
    target_cmake_build jsoncpp src/jsoncpp \
        -DJSONCPP_WITH_CMAKE_PACKAGE=ON \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_STATIC_LIBS=OFF \
        -DJSONCPP_WITH_TESTS=OFF \
        -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF
    append_project_config_to_cmake jsoncpp
}

build_libfunc() {
    target_cmake_build libfunctionality src/libfunctionality \
        -DBUILD_TESTING=OFF
    append_project_config_to_cmake libfunctionality
}

build_libusb() {
    target_ndk_build libusb src/libusb/android/jni
    (
        cd ${ROOT}/src/libusb
        mkdir -p ${INSTALL}/include/libusb-1.0
        cmake -E copy_if_different libusb/libusb.h ${INSTALL}/include/libusb-1.0/libusb.h
    )
}

build_boost() {
    STD_LIBS=llvm
    (
        project=boost
        export LINKAGE=static
        export LIB_LINKAGE=${LINKAGE}
        build=$(target_build_dir ${project})
        mkdir -p ${build}
        cd ${ROOT}/src
        mkdir -p boost
        cd boost
        if [ ! -d ${INSTALL}/boost/${BOOST_VER}/libs/${ANDROID_ABI}/${STD_LIBS} ]; then
            if [ ! -d ${BOOST_VER} ]; then
                wget --timestamping ${BOOST_URL}
                tar xjf ${BOOST_FN}
                mv ${BOOST_FN%.tar.bz2} ${BOOST_VER}
            fi


            (
                cd ${build}
                rm -f boost_build.log
                export ANDROID_NDK_ROOT=${ANDROID_NDK}
                ${ROOT}/src/Boost-for-Android/build_tools/build-boost.sh \
                    --version=$BOOST_VER \
                    --stdlibs=$STD_LIBS \
                    --abis=$ANDROID_ABI \
                    --ndk-dir=$ANDROID_NDK \
                    --linkage=$LINKAGE \
                    --verbose \
                    --install_dir=$INSTALL \
                    --build-dir=$(pwd)/tmp \
                    ${ROOT}/src/boost 2>&1 | tee -a boost_build.log
            )
        fi
    )
    #export BOOST_CMAKE_ARGS="-DBoost_LIBRARY_DIR=${INSTALL}/boost/${BOOST_VER}/libs/${ANDROID_ABI}/${STD_LIBS}  "

    append_to_cmake_args -DBoost_LIBRARY_DIR=${INSTALL}/boost/${BOOST_VER}/libs/${ANDROID_ABI}/${STD_LIBS}
    append_to_cmake_args -DBoost_INCLUDE_DIR=${INSTALL}/boost/${BOOST_VER}/include
    append_to_cmake_args -DBoost_ADDITIONAL_VERSIONS=1.65.1
    append_to_cmake_args -DBoost_USE_STATIC_LIBS=ON
    #export TARGET_CMAKE_PREFIX_PATH="${TARGET_CMAKE_PREFIX_PATH}:${INSTALL}/boost/${BOOST_VER}/libs/${ANDROID_ABI}/${STD_LIBS}:${INSTALL}/boost/${BOOST_VER}/include"
    append_dir_to_cmake ${INSTALL}/boost/${BOOST_VER}/libs/${ANDROID_ABI}/${STD_LIBS}
    append_dir_to_cmake ${INSTALL}/boost/${BOOST_VER}/include
}

build_osvr_core() {
    target_cmake_build OSVR-Core src/OSVR-Core \
        "-DLIBUSB1_LIBRARY=${INSTALL}/lib/libusb1.0.so" \
        "-DLIBUSB1_INCLUDE_DIR=${INSTALL}/include/libusb-1.0" \
        -DOSVR_JSON_TO_C_EXECUTABLE=${OSVR_JSON_TO_C} \
        -DBUILD_WITH_OPENCV=OFF \
        -DBUILD_HEADER_DEPENDENCY_TESTS=OFF

    rm -f ${INSTALL}/lib/cmake/osvr/osvrConfigInstalledOpenCV.cmake
        # "-DVRPN_HIDAPI_SOURCE_ROOT=${ROOT}/src/hidapi" \
}

build_rendermanager() {
    target_cmake_build OSVR-RenderManager src/OSVR-RenderManager \
        "-DEIGEN3_INCLUDE_DIR:PATH=${ROOT}/src/OSVR-Core/vendor/eigen" \
        "-DVRPN_INCLUDE_DIR:PATH=${ROOT}/src/OSVR-Core/vendor/vrpn" \
        "-DVRPN_LIBRARY:PATH=$(target_build_dir OSVR-Core)/bin/libvrpnserver.a" \
        "-DQUATLIB_INCLUDE_DIR:PATH=${ROOT}/src/OSVR-Core/vendor/vrpn/quat" \
        "-DQUATLIB_LIBRARY:PATH=$(target_build_dir OSVR-Core)/bin/libquat.a" \
        "-DCMAKE_CXX_FLAGS:STRING=-std=c++11"
}

(
cd $ROOT
# Host build

build_osvr_json_to_c

append_to_cmake_args "-DOSVR_JSON_TO_C_EXECUTABLE=${OSVR_JSON_TO_C}"

# Target build

# unpack_opencv
build_jsoncpp
build_libfunc
build_libusb
build_boost
build_osvr_core
cp $ANDROID_NDK/sources/cxx-stl/llvm-libc++/libs/${ANDROID_ABI}/libc++_shared.so ${INSTALL}/lib

build_rendermanager

target_cmake_build OSVR-Unity-Rendering src/OSVR-Unity-Rendering

target_cmake_build android_sensor_tracker src/android_sensor_tracker/com_osvr_android_sensorTracker
#target_cmake_build org_osvr_android_moverio src/android_sensor_tracker/org_osvr_android_moverio
target_cmake_build jniImaging src/android_sensor_tracker/com_osvr_android_jniImaging

for proj in src-extra/*; do
    echo $proj
    if [ -d ${proj} -a -f${proj}/CMakeLists.txt ]; then
        target_cmake_build $(basename ${proj}) ${proj}
    fi
done

)