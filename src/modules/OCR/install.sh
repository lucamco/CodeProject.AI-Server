# Development mode setup script ::::::::::::::::::::::::::::::::::::::::::::::
#
#                           OCR
#
# This script is called from the OCR directory using: 
#
#    bash ../../setup.sh
#
# The setup.sh script will find this install.sh file and execute it.

if [ "$1" != "install" ]; then
    read -t 3 -p "This script is only called from: bash ../../setup.sh"
    echo
	exit 1 
fi


message="
*** IF YOU WISH TO USE GPU ON LINUX Please ensure you have CUDA installed ***
# The steps are: (See https://chennima.github.io/cuda-gpu-setup-for-paddle-on-windows-wsl)

sudo apt install libgomp1

# Install CUDA

sudo apt-key del 7fa2af80
wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin
sudo mv cuda-wsl-ubuntu.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/11.7.0/local_installers/cuda-repo-wsl-ubuntu-11-7-local_11.7.0-1_amd64.deb
sudo dpkg -i cuda-repo-wsl-ubuntu-11-7-local_11.7.0-1_amd64.deb

sudo cp /var/cuda-repo-wsl-ubuntu-11-7-local/cuda-B81839D3-keyring.gpg /usr/share/keyrings/

sudo apt-get update
sudo apt-get -y install cuda

# Now Install cuDNN

sudo apt-get install zlib1g

# => Go to https://developer.nvidia.com/cudnn, sign in / sign up, agree to terms 
#    and download 'Local Installer for Linux x86_64 (Tar)'. This will download a
#    file similar to 'cudnn-linux-x86_64-8.4.1.50_cuda11.6-archive.tar.xz'
#
# In the downloads folder do: 

tar -xvf cudnn-linux-x86_64-8.4.1.50_cuda11.6-archive.tar.xz
sudo cp cudnn-*-archive/include/cudnn*.h /usr/local/cuda/include 
sudo cp -P cudnn-*-archive/lib/libcudnn* /usr/local/cuda/lib64 
sudo chmod a+r /usr/local/cuda/include/cudnn*.h /usr/local/cuda/lib64/libcudnn*

# and you'll be good to go
"
# print message


# Install python and the required dependencies.

# Note that PaddlePaddle requires Python3.8 or below. Except on RPi? TODO: check 3.9 on all.
if [ ! "${hardware}" == "RaspberryPi" ]; then
    setupPython 3.8 "LocalToModule"
    installPythonPackages 3.8 "${modulePath}" "LocalToModule"
    installPythonPackages 3.8 "${absoluteAppRootDir}/SDK/Python" "LocalToModule"
fi

# Download the OCR models and store in /paddleocr
getFromServer "paddleocr-models.zip" "paddleocr" "Downloading OCR models..."

# We have a patch to apply for linux. 
if [ "${platform}" = "linux" ]; then
    if [ "${hasCUDA}" != "true" ]; then
        # writeLine 'Applying PaddlePaddle patch'
        # https://www.codeproject.com/Tips/5347636/Getting-PaddleOCR-and-PaddlePaddle-to-work-in-Wind
        # NOT Needed for Ubuntu 20.04 WSL under Win10
        # cp ${modulePath}/patch/paddle2.4.0rc0/image.py ${modulePath}/bin/${platform}/python38/venv/lib/python3.8/site-packages/paddle/dataset/.

        writeLine 'Applying PaddleOCR patch'
        # IS needed due to a newer version of Numpy deprecating np.int
        cp ${modulePath}/patch/paddle2.4.0rc0/db_postprocess.py ${modulePath}/bin/${platform}/python38/venv/lib/python3.8/site-packages/paddleocr/ppocr/postprocess/.
    fi
fi

# We have a patch to apply for macOS-arm64 due to numpy upgrade that deprecates np.int that we can't downgrade
if [ "${os}" == "macos" ]; then
    writeLine 'Applying PaddleOCR patch'
    cp ${modulePath}/patch/paddleocr2.6.0.1/db_postprocess.py ${modulePath}/bin/${os}/python38/venv/lib/python3.8/site-packages/paddleocr/ppocr/postprocess/.
fi

# Installig PaddlePaddle: Gotta do this the hard way for RPi.
# Thanks to https://qengineering.eu/install-paddlepaddle-on-raspberry-pi-4.html
# NOTE: This, so far, hasn't been working. Sorry.
if [ "${hardware}" == "RaspberryPi" ]; then

    setupPython 3.9 "LocalToModule"
    installPythonPackages 3.9 "${modulePath}" "LocalToModule"
    installPythonPackages 3.9 "${absoluteAppRootDir}/SDK/Python" "LocalToModule"

    popd "${modulePath}"

    # a fresh start
    sudo apt-get update -y
    sudo apt-get upgrade -y
    # install dependencies
    sudo apt-get install cmake wget -y
    sudo apt-get install libatlas-base-dev libopenblas-dev libblas-dev -y
    sudo apt-get install liblapack-dev patchelf gfortran -y

    cd ./bin/linux/python38/venv/bin

    sudo -H ./pip3 install Cython
    sudo -H ./pip3 install -U setuptools
    ./pip3 install six requests wheel pyyaml
    # upgrade version 3.0.0 -> 3.13.0
    ./pip3 install -U protobuf
    # download the wheel
    wget https://github.com/Qengineering/Paddle-Raspberry-Pi/raw/main/paddlepaddle-2.0.0-cp37-cp37m-linux_aarch64.whl
    # install Paddle
    sudo -H ./pip3 install paddlepaddle-2.0.0-cp37-cp37m-linux_aarch64.whl
    # clean up
    rm paddlepaddle-2.0.0-cp37-cp37m-linux_aarch64.whl

    popd
fi

#                         -- Install script cheatsheet -- 
#
# Variables available:
#
#  absoluteRootDir       - the root path of the installation (eg: ~/CodeProject/AI)
#  sdkScriptsPath       - the path to the installation utility scripts ($rootPath/Installers)
#  downloadPath          - the path to where downloads will be stored ($sdkScriptsPath/downloads)
#  installedModulesPath  - the path to the pre-installed AI modules ($rootPath/src/AnalysisLayer)
#  downloadedModulesPath - the path to the download AI modules ($rootPath/src/modules)
#  moduleDir             - the name of the directory containing this module
#  modulePath            - the path to this module ($installedModulesPath/$moduleDir or
#                          $downloadedModulesPath/$moduleDir, depending on whether pre-installed)
#  os                    - "linux" or "macos"
#  architecture          - "x86_64" or "arm64"
#  platform              - "linux", "linux-arm64", "macos" or "macos-arm64"
#  verbosity             - quiet, info or loud. Use this to determines the noise level of output.
#  forceOverwrite        - if true then ensure you force a re-download and re-copy of downloads.
#                          getFromServer will honour this value. Do it yourself for downloadAndExtract 
#
# Methods available
#
#  write     text [foreground [background]] (eg write "Hi" "green")
#  writeLine text [foreground [background]]
#  Download  storageUrl downloadPath filename moduleDir message
#        storageUrl    - Url that holds the compressed archive to Download
#        downloadPath  - Path to where the downloaded compressed archive should be downloaded
#        filename      - Name of the compressed archive to be downloaded
#        dirNameToSave - name of directory, relative to downloadPath, where contents of archive 
#                        will be extracted and saved
#
#  getFromServer filename moduleAssetDir message
#        filename       - Name of the compressed archive to be downloaded
#        moduleAssetDir - Name of folder in module's directory where archive will be extracted
#        message        - Message to display during download
#
#  downloadAndExtract  storageUrl filename downloadPath dirNameToSave message
#        storageUrl    - Url that holds the compressed archive to Download
#        filename      - Name of the compressed archive to be downloaded
#        downloadPath  - Path to where the downloaded compressed archive should be downloaded
#        dirNameToSave - name of directory, relative to downloadPath, where contents of archive 
#                        will be extracted and saved
#        message       - Message to display during download
#
#  setupPython Version [install-location]
#       Version - version number of python to setup. 3.8 and 3.9 currently supported. A virtual
#                 environment will be created in the module's local folder if install-location is
#                 "LocalToModule", otherwise in $installedModulesPath/bin/$platform/python<version>/venv.
#       install-location - [optional] "LocalToModule" or "Shared" (see above)
#
#  installPythonPackages Version requirements-file-directory
#       Version - version number, as per SetupPython
#       requirements-file-directory - directory containing the requirements.txt file
#       install-location - [optional] "LocalToModule" (installed in the module's local venv) or 
#                          "Shared" (installed in the shared $installedModulesPath/bin venv folder)