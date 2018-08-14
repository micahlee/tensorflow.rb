#!/bin/bash

# Global Configurations
TENSORFLOW_GPU_ENABLED="n"
pip install --upgrade pip
apt-get install python-pip python-dev
pip install tensorflow
# Change dir to shell script dir
cd $(dirname $0)

# Check current Platform
platform="linux"

if [ "$(uname)" == "Darwin" ]; then
	platform="darwin" # Mac OSX
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
	platform="linux"
elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
	platform="windows"
fi

# 
# Package URL Source codes
# 

# pkg-config
PKG_CONFIG="http://pkgconfig.freedesktop.org/releases/pkg-config-0.28.tar.gz"

# Bazel Source
BAZEL_ROOT="https://github.com/bazelbuild/bazel/releases/download"
BAZEL_VERS="0.15.2"
PKG_BAZEL="$BAZEL_ROOT/$BAZEL_VERS/bazel-$BAZEL_VERS-installer-$platform-x86_64.sh"

# TensorFlow source
TENSORFLOW="https://github.com/tensorflow/tensorflow"

PREFIX=${1-/usr/local}

echo "=== Installing TensorFlow for $platform ==="

require() {
	if test `which $1`; then
		echo "= $1: Found"
	else
		echo "= $1: Not found"
		exit 1
	fi
}

install_shell() {
	local url=$1
	local name=`basename $url`

	echo ""
	echo "= Installing $name" \
	 && echo "== Downloading $name" \
	 && curl -# -L $url -o $name \
	 && echo "== Changing file to execute mode..." \
	 && chmod +x $name \
	 || exit 1

 	echo "== Installing..."
	if ./$name --user; then

		rm $name
	 	echo "== Sucessfully installed $name"

	else

	 	echo "! Failed to install $name"
	 	rm $name
	 	exit 1

	fi

}

make_install() {
	local dir=$1

	echo ""
	echo "= installing $1 $2"

 	cd $dir \
	 && ./configure --disable-dependency-tracking --prefix=$PREFIX $2 \
	 && make \
	 && make install \
	 && echo "... removing $dir" \
	 && cd .. && rm -fr $dir
}

fetch() {
	local tarball=`basename $1`
	local dir=`basename $tarball .tar.gz`

	echo ""
	echo "= downloading $tarball $2"
	curl -# -L $1 -o $tarball \
		&& echo "== unpacking" \
		&& tar -zxf $tarball \
		&& echo "== removing tarball" \
		&& rm -fr $tarball \
		&& make_install $dir $2
}

clone(){
	local repo=$1
	local folderName=$2

	echo ""
	echo "= cloning $folderName [url: $repo]"

	# Remove folder before cloning
	rm -rf $folderName

	# Git clone the repo
	git clone --recurse-submodules $repo ./$folderName
}

install(){
	# Target OS to install
	local os=$1
	# Name of the package
	local name=$2

	# Check if is target OS
	if [ "$platform" != "$os" ]; then
		echo "= $name skipped (not in $os)"
		return
	fi

	# Check if package already installed
	if hash $name 2>/dev/null; then
		echo "= $name already installed"
		return
	fi

	if [ "$platform" == "linux" ]; then

		# Install for Linux
		if hash apt-get 2>/dev/null; then
			echo  ""
			echo "= installing with apt-get: $name"

			apt-get install $name -y
		else
			echo "! apt-get not installed"
			exit 1
		fi
	elif [ "$platform" == "darwin" ]; then
		
		# Install for Mac OSX
		if hash brew 2>/dev/null; then
			echo ""
			echo "= installing with brew: $name"

			brew install $name -y
		else
			echo "! brew not installed"
			exit 1
		fi
	fi
}

echo ""
echo "= installing to $PREFIX"

# 
# Install JDK 8, ONLY if JDK (javac) is not installed
# 
if ! which javac; then
	echo ""
	echo "= No JDK installed. Installing JDK 8"
	add-apt-repository ppa:webupd8team/java
	apt-get update
	install linux "oracle-java8-installer"
	install linux "oracle-java8-set-default"
fi

# Check for JDK 8
JAVA_VER=$(javac -version 2>&1 | sed 's/javac \(.*\)\.\(.*\)\..*/\1\2/; 1q')

if [ "$JAVA_VER" != "18" ]; then
	echo ""
	echo "JAVAC version is not JDK 8. Current version: $JAVA_VER"
	exit 1
fi

# Check for dependencies that needs to be installed
require git
require curl
require javac

# Check for pkg-config and install if needed
test `which pkg-config` || fetch $PKG_CONFIG --with-internal-glib
require 'pkg-config'

# Install Bazel Dependencies
install linux "zip"
install linux "g++"
install linux "zlib1g-dev"
install linux "unzip"

# Install SWIG and ruby dependencies
install linux "swig"
install linux "ruby-dev"
install linux "ruby-bundler"

# Install protobuf dependencies
install linux "dh-autoreconf"

# Install Bazel
# 
# Export path if not yet saved
if [[ ! ":$PATH:" == *":$HOME/bin:"* ]]; then
	echo '' >> ~/.bash_profile
	echo '# Required by Bazel' >> ~/.bash_profile
	echo 'export PATH=$PATH:'"$HOME/bin" >> ~/.bash_profile

	echo "= Saved $HOME/bin to ~/.bash_profile"
fi
# Do installation (check before)
export PATH="$PATH:$HOME/bin"

if hash bazel 2>/dev/null; then
	echo "= Bazel already installed"
else
	install_shell $PKG_BAZEL
fi
export PATH=$PATH:$HOME/bin
# 
# Clone TensorFlow Repo
clone $TENSORFLOW "tensorflow"

# Go to tensorflow dir
cd "tensorflow"

# Configure TensorFlow (with/without GPU)
echo ""
echo "= Configuring TensorFlow (GPU: $TENSORFLOW_GPU_ENABLED)"
./configure

# Compile TensorFlow
echo ""
echo "= Compiling TensorFlow"

# Bazel 
# If you are behind a proxy then you need to define proxy here to work with bazel.
# export http_proxy=http:// 
# export https_proxy=https:// 
bazel  build -c opt //tensorflow:libtensorflow.so --local_resources 2048,.5,1.0
cp bazel-bin/tensorflow/libtensorflow.so /usr/lib/
cp bazel-bin/tensorflow/libtensorflow_framework.so /usr/lib   

#moving out of tensorflow clone
cd ./..

#cloning tensorflow.rb
git clone https://github.com/somaticio/tensorflow.rb.git
cd tensorflow.rb/ext/sciruby/tensorflow_c
ruby extconf.rb
make
make install # Creates ../lib/ruby/site_ruby/X.X.X/<arch>/tf/Tensorflow.bundle (.so Linux)
cd ./../../..
bundle install
bundle exec rake install

echo ""
echo "Thank you for installing tensorflow.rb"
