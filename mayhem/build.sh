#!/bin/bash -eu
# Copyright 2019 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################

# Force DWARF 4 to avoid ld FORM 0x25 errors with clang 22 + old binutils.
export CFLAGS="-gdwarf-4 $CFLAGS"
export CXXFLAGS="-gdwarf-4 $CXXFLAGS"

# Build dependencies.
export DEPS_PATH=$SRC/deps
mkdir -p $DEPS_PATH

# ---- x265 (CMake) ----
cd $SRC/x265/build/linux
cmake -G "Unix Makefiles" \
    -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PATH" \
    -DENABLE_SHARED:bool=off \
    ../../source
make clean
make -j$(nproc) x265-static
make install

# ---- libde265 (CMake — autogen.sh removed from master branch) ----
mkdir -p $SRC/libde265/build
cd $SRC/libde265/build
cmake -G "Unix Makefiles" \
    -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PATH" \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_DECODER=ON \
    -DENABLE_ENCODER=OFF \
    ..
make clean
make -j$(nproc)
make install

# ---- aom (CMake) ----
mkdir -p $SRC/aom/build/linux
cd $SRC/aom/build/linux
cmake -G "Unix Makefiles" \
  -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX \
  -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
  -DCMAKE_INSTALL_PREFIX="$DEPS_PATH" \
  -DENABLE_SHARED:bool=off -DCONFIG_PIC=1 \
  -DENABLE_EXAMPLES=0 -DENABLE_DOCS=0 -DENABLE_TESTS=0 \
  -DCONFIG_SIZE_LIMIT=1 \
  -DDECODE_HEIGHT_LIMIT=12288 -DDECODE_WIDTH_LIMIT=12288 \
  -DDO_RANGE_CHECK_CLAMP=1 \
  -DAOM_MAX_ALLOCABLE_MEMORY=536870912 \
  -DAOM_TARGET_CPU=generic \
  ../../
make clean
make -j$(nproc)
make install

# Remove shared libraries to avoid accidental linking against them.
rm -f $DEPS_PATH/lib/*.so
rm -f $DEPS_PATH/lib/*.so.*

# ---- libheif (CMake with fuzzers) ----
mkdir -p $SRC/libheif/build
cd $SRC/libheif/build
cmake -G "Unix Makefiles" \
    -DCMAKE_PREFIX_PATH="$DEPS_PATH" \
    -DWITH_FUZZERS=ON \
    -DFUZZING_C_COMPILER="$CC" \
    -DFUZZING_CXX_COMPILER="$CXX" \
    -DFUZZING_COMPILE_OPTIONS="$CXXFLAGS" \
    -DFUZZING_LINKER_OPTIONS="$LIB_FUZZING_ENGINE" \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_LIBDE265=ON \
    -DWITH_X265=ON \
    -DWITH_AOM_ENCODER=ON \
    -DWITH_AOM_DECODER=ON \
    ..
make -j$(nproc)

# CMake produces underscore-named binaries (box_fuzzer, file_fuzzer, etc.)
cp fuzzing/box_fuzzer $OUT/box-fuzzer
cp fuzzing/file_fuzzer $OUT/file-fuzzer
cp fuzzing/encoder_fuzzer $OUT/encoder-fuzzer
cp fuzzing/color_conversion_fuzzer $OUT/color-conversion-fuzzer
cp $SRC/libheif/fuzzing/data/dictionary.txt $OUT/box-fuzzer.dict
cp $SRC/libheif/fuzzing/data/dictionary.txt $OUT/file-fuzzer.dict

zip -r $OUT/file-fuzzer_seed_corpus.zip $SRC/libheif/fuzzing/data/corpus/*.heic
